import AIMCore
import AppKit
import SwiftUI

/// Creates and tracks the app's AppKit windows, each hosting a SwiftUI view.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    let app: AppController
    let skin: SkinStore
    private(set) var basePATH: String?
    private var signOnWindow: NSWindow?
    private var buddyListWindow: NSWindow?
    var chatWindows: [UUID: NSWindow] = [:]
    var attention: Set<UUID> = [] { didSet { refreshBuddyList() } }
    private var dialogs: [NSWindow] = []
    /// One controller per buddy, kept while the app runs so a turn survives its window closing.
    private(set) var chats: [UUID: ChatController] = [:]

    init(app: AppController, skin: SkinStore) {
        self.app = app
        self.skin = skin
    }

    let broker = PermissionBroker()
    private var server: MCPServer?

    func start() {
        startPermissionServer()
        if app.showsSignOn { showSignOn() } else { showBuddyList() }
        if let e = app.loadError { showDialog(e) }
        locateClaude()
    }

    /// Without the server, buddies still work; unapproved tools are just denied as in plain `claude -p`.
    private func startPermissionServer() {
        let server = MCPServer(broker: broker, configDirectory: AppPaths.support.appendingPathComponent("mcp"))
        self.server = server
        Task {
            await broker.setObserver { r in
                Task { @MainActor [weak self] in self?.permissionRequested(r) }
            }
            do {
                try await server.start()
                mcpConfigPath = { id in try? server.configPath(for: id) }
            } catch {
                self.server = nil
                showDialog("AIM couldn't start its permission helper, so buddies can't ask before running commands: \(error.localizedDescription)")
            }
        }
    }

    private func permissionRequested(_ r: PermissionRequest) {
        chatController(for: r.buddyID).addPermission(r)
        attention.insert(r.buddyID)
        app.sounds.play(.message)
        openChat(r.buddyID)
        NSApp.requestUserAttention(.informationalRequest)
    }

    func shutdown() {
        SystemProcessLauncher.terminateAll()
        server?.stop()
    }

    func locateClaude() {
        let override = app.state.claudePathOverride
        Task.detached {
            let shell = LoginShell()
            let result = Result { try ClaudeLocator.locate(override: override, shell: shell) }
            let path = (try? shell.run("print -r -- $PATH"))?
                .split(whereSeparator: \.isNewline).last { $0.hasPrefix("/") }.map(String.init)
            await MainActor.run {
                self.basePATH = path
                self.app.applyLocatorResult(result.mapError { $0 as any Error })
                Log.app.notice("claude: \(self.app.claudePath?.path ?? "not found", privacy: .public)")
                if self.app.claudeMissing {
                    self.showDialog("AIM couldn't find the claude command. Install Claude Code, or set its path in Preferences.")
                }
            }
        }
    }

    // MARK: windows

    func showSignOn() {
        buddyListWindow?.close()
        buddyListWindow = nil
        let view = SignOnView(app: app, skin: skin,
                              onSignedOn: { [weak self] in self?.showBuddyList() },
                              onHelp: { [weak self] in self?.showAbout() },
                              onSetup: { [weak self] in self?.showPreferences() })
        let w = makeWindow(title: "Sign On", resizable: false, view: view)
        signOnWindow = w
        w.center()
        w.makeKeyAndOrderFront(nil)
    }

    func showBuddyList() {
        signOnWindow?.close()
        signOnWindow = nil
        if let w = buddyListWindow { w.makeKeyAndOrderFront(nil); return }
        let w = makeWindow(title: buddyListTitle, resizable: true, view: buddyListView())
        w.setContentSize(NSSize(width: 240, height: 520))
        w.setFrameAutosaveName("BuddyList")
        buddyListWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    private func buddyListView() -> BuddyListView {
        BuddyListView(app: app, skin: skin, attention: attention, actions: BuddyListActions(
            openChat: { [weak self] in self?.openChat($0) },
            addBuddy: { [weak self] in self?.addBuddy() },
            signOff: { [weak self] in self?.signOff() },
            changeScreenName: { [weak self] in self?.changeScreenName() },
            preferences: { [weak self] in self?.showPreferences() },
            getInfo: { [weak self] in self?.showInfo($0) },
            about: { [weak self] in self?.showAbout() }))
    }

    private var buddyListTitle: String { "\(app.state.screenName ?? "")'s Buddy List" }

    func showInfo(_ id: UUID) {
        guard let b = app.buddy(id) else { return }
        showDialog("\(b.screenName)\n\nWorks in: \(b.workingDirectory.path)\nClaude session: \(b.sessionID.uuidString.lowercased())\nMessages: \(b.messages.count)",
                   symbol: "person.text.rectangle")
    }

    func showAbout() {
        showDialog("AIM for Claude\nVersion 0.1\n\nEach buddy is its own Claude Code session.", symbol: "info.circle.fill")
    }

    private func refreshBuddyList() {
        (buddyListWindow?.contentViewController as? NSHostingController<AnyView>)?.rootView = AnyView(buddyListView())
        buddyListWindow?.title = buddyListTitle
    }

    func openChat(_ id: UUID) {
        if let w = chatWindows[id] { w.makeKeyAndOrderFront(nil); return }
        guard let buddy = app.buddy(id) else { return }
        var window: NSWindow?
        let view = ChatView(chat: chatController(for: id), myName: { [weak self] in self?.app.state.screenName ?? "Me" },
                            actions: ChatActions(addBuddy: { [weak self] in self?.addBuddy() },
                                                 getInfo: { [weak self] in self?.showInfo(id) },
                                                 close: { window?.performClose(nil) }))
        let w = makeWindow(title: buddy.screenName, resizable: true, view: view)
        window = w
        w.setContentSize(NSSize(width: 440, height: 380))
        w.setFrameAutosaveName("Chat-\(id.uuidString)")
        chatWindows[id] = w
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
    }

    func chatController(for id: UUID) -> ChatController {
        if let c = chats[id] { return c }
        let c = ChatController(buddyID: id, app: app) { [weak self] in self?.makeChannel(for: id) }
        let broker = broker
        c.onResolvePermission = { [weak self, weak c] rid, decision in
            Task { await broker.resolve(rid, decision) }
            if c?.needsAttention == false { self?.attention.remove(id) }
        }
        c.onTurnEnded = { [weak self] in
            Task { await broker.cancelAll(buddyID: id) }
            self?.attention.remove(id)
        }
        // AIM popped the IM window open when a message arrived.
        c.onReply = { [weak self] in
            guard let self, self.app.state.signedOn, self.chatWindows[id] == nil else { return }
            self.openChat(id)
        }
        chats[id] = c
        return c
    }

    private func makeChannel(for id: UUID) -> (any BuddyChanneling)? {
        guard let buddy = app.buddy(id), let claude = app.claudePath else { return nil }
        let broker = broker
        return BuddyChannel(buddy: buddy, claudePath: claude, mcpConfigPath: mcpConfigPath(id),
                            launcher: SystemProcessLauncher(basePATH: basePATH),
                            permissionPending: { await broker.pending.contains { $0.buddyID == id } })
    }

    /// Set up by the permission server; nil means no permission prompts.
    var mcpConfigPath: (UUID) -> URL? = { _ in nil }

    func addBuddy() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Add Buddy"
        panel.message = "Choose the folder \(BuddyNamer.nextName(existing: app.state.buddies.map(\.screenName))) will work in."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let b = app.addBuddy(workingDirectory: url)
        refreshBuddyList()
        openChat(b.id)
    }

    func signOff() {
        for w in chatWindows.values { w.close() }
        chatWindows.removeAll()
        app.signOff()
        showSignOn()
    }

    func changeScreenName() {
        let field = State(initialValue: app.state.screenName ?? "")
        var window: NSWindow?
        let view = ScreenNamePrompt(name: field) { [weak self] newName in
            if let newName { self?.app.setScreenName(newName); self?.refreshBuddyList() }
            window?.close()
        }
        window = makeWindow(title: "Change Screen Name", resizable: false, view: view)
        dialogs.append(window!)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private var preferencesWindow: NSWindow?

    func showPreferences() {
        if let w = preferencesWindow { w.makeKeyAndOrderFront(nil); return }
        let view = PreferencesView(app: app) { [weak self] in self?.locateClaude() }
        let w = makeWindow(title: "Preferences", resizable: false, view: view)
        preferencesWindow = w
        w.center()
        w.makeKeyAndOrderFront(nil)
    }

    func showDialog(_ message: String, symbol: String = "exclamationmark.triangle.fill") {
        var window: NSWindow?
        let view = AIMDialog(message: message, symbol: symbol) { window?.close() }
        window = makeWindow(title: "AIM", resizable: false, view: view)
        dialogs.append(window!)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func makeWindow<V: View>(title: String, resizable: Bool, view: V) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let host = NSHostingController(rootView: AnyView(view))
        host.sizingOptions = resizable ? [.minSize] : [.preferredContentSize]
        let w = NSWindow(contentViewController: host)
        w.styleMask = style
        w.setContentSize(host.view.fittingSize)
        w.title = title
        w.backgroundColor = NSColor(white: 0.753, alpha: 1)
        w.isReleasedWhenClosed = false
        return w
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        if let id = chatWindows.first(where: { $0.value === w })?.key { chatWindows[id] = nil }
        dialogs.removeAll { $0 === w }
    }
}

private struct ScreenNamePrompt: View {
    let name: State<String>
    let done: (String?) -> Void

    var body: some View {
        AIMDialog(message: "Enter a new screen name:", symbol: "person.fill", field: name.projectedValue,
                  primary: "OK", secondary: "Cancel",
                  onPrimary: { done(name.wrappedValue) }, onSecondary: { done(nil) })
    }
}
