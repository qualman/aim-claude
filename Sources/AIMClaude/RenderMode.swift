import AIMCore
import AppKit
import SwiftUI

/// Dev tool: `AIMClaude --render <dir>` writes PNGs of each screen and exits.
/// Lets the look be checked without screen-recording permission.
@MainActor
enum RenderMode {
    static var screens: [(String, AnyView)] {
        let skin = SkinStore(directory: AppPaths.skin)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("aim-render-\(UUID().uuidString)")
        let app = AppController(store: StateStore(directory: tmp), sounds: SilentSoundPlayer())
        app.signOn(screenName: "SkaterBoi99")
        let a = app.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        let b = app.addBuddy(workingDirectory: URL(fileURLWithPath: "/tmp"))
        return [
            ("gallery", AnyView(LookGallery())),
            ("signon", AnyView(SignOnView(app: app, skin: skin) {})),
            ("buddylist", AnyView(BuddyListView(app: app, skin: skin, attention: [a.id], actions: BuddyListActions())
                .frame(width: 240, height: 520))),
            ("buddylist-selected", AnyView(BuddyListView(app: app, skin: skin, selected: b.id, actions: BuddyListActions())
                .frame(width: 240, height: 520))),
            ("dialog", AnyView(AIMDialog(message: "AIM couldn't find the claude command. Install Claude Code, or set its path in Preferences.") {})),
        ] + extraScreens(app: app, skin: skin)
    }

    /// Later screens register here.
    static func extraScreens(app: AppController, skin: SkinStore) -> [(String, AnyView)] {
        guard let b = app.state.buddies.first else { return [] }
        app.updateBuddy(b.id) {
            $0.messages = [
                ChatMessage(sender: .user, text: "hey can you look at my build script"),
                ChatMessage(sender: .buddy, text: "Sure. The problem is on line 4:\n\n    swift build -c release\n\nshould pass --product AIMClaude."),
                ChatMessage(sender: .system, text: "xX_Claude_Xx's Claude session was lost, so it started a new one."),
                ChatMessage(sender: .error, text: "claude exited with status 1: boom"),
            ]
        }
        let chat = ChatController(buddyID: b.id, app: app) { nil }
        chat.apply(.activity("Reading build-app.sh"))
        chat.addPermission(PermissionRequest(id: UUID(), buddyID: b.id, toolName: "Bash", inputSummary: "Running: swift build -c release"))
        app.applyLocatorResult(.success(URL(fileURLWithPath: "/usr/local/bin/claude")))
        return [("preferences", AnyView(PreferencesView(app: app) {})), ("chat", AnyView(ChatView(chat: chat, myName: { "SkaterBoi99" }).frame(width: 440, height: 420)))]
    }

    /// `--snapshot <dir>`: after launch, write each visible window (with its title bar) as PNG, then quit.
    static func scheduleSnapshotIfRequested(delay: TimeInterval = 4) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            for (n, w) in NSApp.windows.filter(\.isVisible).enumerated() {
                guard let frameView = w.contentView?.superview,
                      let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { continue }
                frameView.cacheDisplay(in: frameView.bounds, to: rep)
                let name = "\(n)-\(w.title.replacingOccurrences(of: " ", with: "_")).png"
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
            }
            exit(0)
        }
    }

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render"), i + 1 < args.count else { return }
        Skin.registerFonts()
        SkinButton.previewHover = ProcessInfo.processInfo.environment["AIM_RENDER_HOVER"] == "1"
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, view) in screens {
            // A real NSHostingView in an offscreen window, so AppKit-backed views (fields, scroll views) draw too.
            let host = NSHostingView(rootView: view.environment(\.colorScheme, .light))
            let size = host.fittingSize
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
        }
        exit(0)
    }
}

struct LookGallery: View {
    private let text = State(initialValue: "SkaterBoi99")

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Raised").font(AIMFonts.label).frame(width: 90, height: 40).background(AIMColors.window).bevelRaised()
                Text("Sunken").font(AIMFonts.label).frame(width: 90, height: 40).background(AIMColors.field).bevelSunken()
            }
            HStack(spacing: 8) {
                Button("Sign On") {}.buttonStyle(AIMButtonStyle(isDefault: true))
                Button("Cancel") {}.buttonStyle(AIMButtonStyle())
                AIMToolbarButton(title: "IM", symbol: "bubble.left") {}
            }
            AIMTextField(placeholder: "Screen Name", text: text.projectedValue).frame(width: 200)
            VStack(alignment: .leading, spacing: 2) {
                (Text("SkaterBoi99: ").font(AIMFonts.messageBold).foregroundColor(AIMColors.userName)
                 + Text("hey whats up").font(AIMFonts.message))
                (Text("xX_Claude_Xx: ").font(AIMFonts.messageBold).foregroundColor(AIMColors.buddyName)
                 + Text("func hello() { print(\"hi\") }").font(AIMFonts.message))
            }
            .padding(6)
            .frame(width: 320, alignment: .leading)
            .background(AIMColors.field)
            .bevelSunken()
        }
        .padding(12)
        .background(AIMColors.window)
    }
}
