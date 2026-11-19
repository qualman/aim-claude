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
        let skin = SkinStore(directory: AppPaths.skin)
        let app = AppController(store: StateStore(directory: AppPaths.support), sounds: SoundPlayer(skin: skin))
        windows = WindowManager(app: app, skin: skin)
        NSApp.mainMenu = MainMenu.build(target: self)
        windows.start()
        if ProcessInfo.processInfo.environment["AIM_OPEN_CHATS"] == "1" {
            for b in app.state.buddies { windows.openChat(b.id) }
        }
        RenderMode.scheduleSnapshotIfRequested()
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
