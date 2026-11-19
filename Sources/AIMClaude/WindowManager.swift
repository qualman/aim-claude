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
    /// Set by later tasks to build chat windows.
    var makeChatWindow: ((UUID) -> NSWindow?)?

    init(app: AppController, skin: SkinStore) {
        self.app = app
        self.skin = skin
    }

    func start() {
        if app.showsSignOn { showSignOn() } else { showBuddyList() }
        if let e = app.loadError { showDialog(e) }
        locateClaude()
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
        let w = makeWindow(title: "Sign On", resizable: false, view: SignOnView(app: app, skin: skin) { [weak self] in
            self?.showBuddyList()
        })
        signOnWindow = w
        w.center()
        w.makeKeyAndOrderFront(nil)
    }

    func showBuddyList() {
        signOnWindow?.close()
        signOnWindow = nil
        if let w = buddyListWindow { w.makeKeyAndOrderFront(nil); return }
        let w = makeWindow(title: "Buddy List", resizable: true, view: buddyListView())
        w.setContentSize(NSSize(width: 230, height: 480))
        w.setFrameAutosaveName("BuddyList")
        buddyListWindow = w
        w.makeKeyAndOrderFront(nil)
    }

    private func buddyListView() -> BuddyListView {
        BuddyListView(app: app, skin: skin, attention: attention,
                      onOpenChat: { [weak self] in self?.openChat($0) },
                      onAddBuddy: { [weak self] in self?.addBuddy() },
                      onSignOff: { [weak self] in self?.signOff() })
    }

    private func refreshBuddyList() {
        (buddyListWindow?.contentViewController as? NSHostingController<AnyView>)?.rootView = AnyView(buddyListView())
    }

    func openChat(_ id: UUID) {
        if let w = chatWindows[id] { w.makeKeyAndOrderFront(nil); return }
        guard let w = makeChatWindow?(id) else { return }
        chatWindows[id] = w
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
    }

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

    func showDialog(_ message: String) {
        var window: NSWindow?
        let view = AIMDialog(message: message) { window?.close() }
        window = makeWindow(title: "AIM", resizable: false, view: view)
        dialogs.append(window!)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func makeWindow<V: View>(title: String, resizable: Bool, view: V) -> NSWindow {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let host = NSHostingController(rootView: AnyView(view))
        let w = NSWindow(contentViewController: host)
        w.styleMask = style
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
