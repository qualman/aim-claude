import AIMCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var windows: WindowManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let skin = SkinStore(directory: AppPaths.skin)
        let app = AppController(store: StateStore(directory: AppPaths.support), sounds: SoundPlayer(skin: skin))
        windows = WindowManager(app: app, skin: skin)
        NSApp.mainMenu = MainMenu.build(target: self)
        windows.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

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
