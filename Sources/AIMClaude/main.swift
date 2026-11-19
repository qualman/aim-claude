import AIMCore
import AppKit
import os

enum Log {
    static let app = Logger(subsystem: "local.aimclaude", category: "app")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: WindowManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Each IM is its own window, as in AIM; macOS would otherwise merge them into tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
        Skin.registerFonts()
        let skin = SkinStore(directory: AppPaths.skin)
        let app = AppController(store: StateStore(directory: AppPaths.support), sounds: SoundPlayer(skin: skin))
        windows = WindowManager(app: app, skin: skin)
        NSApp.mainMenu = MainMenu.build(target: self)
        windows.start()
        if ProcessInfo.processInfo.environment["AIM_OPEN_CHATS"] == "1" {
            for b in app.state.buddies { windows.openChat(b.id) }
        }
        RenderMode.scheduleSnapshotIfRequested()
        scheduleTransitionCheckIfRequested(app: app)
    }

    /// Dev check: AIM_TRANSITION_CHECK=<file> runs Sign On → Buddy List → Sign Off → Sign On the way the
    /// buttons do, then writes <file> and quits. If a transition quits the app, the file never appears.
    private func scheduleTransitionCheckIfRequested(app: AppController) {
        guard let marker = ProcessInfo.processInfo.environment["AIM_TRANSITION_CHECK"] else { return }
        if ProcessInfo.processInfo.environment["AIM_TRANSITION_KEY"] == "1" {
            // Press Return in the Sign On window: the real event path into the button's default-action shortcut.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                guard let w = NSApp.windows.first(where: { $0.title == "Sign On" }) else { return }
                NSApp.activate()
                w.makeKeyAndOrderFront(nil)
                // Sign On sits bottom-right, above the version line.
                let pt = NSPoint(x: w.contentLayoutRect.maxX - 32, y: 46)
                func click(_ type: NSEvent.EventType) {
                    if let e = NSEvent.mouseEvent(with: type, location: pt, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        NSApp.sendEvent(e)
                    }
                }
                // Hold the button like a person does, so the pressed state renders before release.
                click(.leftMouseDown)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { click(.leftMouseUp) }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if app.signOn(screenName: "TransitionCheck") { self.windows.showBuddyList() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.windows.signOff() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let open = NSApp.windows.filter(\.isVisible).map(\.title)
            try? "survived; signedOn=\(app.state.signedOn); open windows: \(open)".write(toFile: marker, atomically: true, encoding: .utf8)
            exit(0)
        }
    }

    func applicationWillTerminate(_ notification: Notification) { windows.shutdown() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc func showPreferences(_ sender: Any?) { windows.showPreferences() }
    @objc func changeScreenName(_ sender: Any?) { windows.changeScreenName() }
    @objc func addBuddy(_ sender: Any?) { windows.addBuddy() }
    @objc func signOff(_ sender: Any?) { windows.signOff() }
}

MainActor.assumeIsolated {
    RenderMode.runIfRequested()
    let delegate = AppDelegate()
    NSApplication.shared.delegate = delegate
    NSApplication.shared.setActivationPolicy(.regular)
    NSApplication.shared.activate()
    NSApplication.shared.run()
}
