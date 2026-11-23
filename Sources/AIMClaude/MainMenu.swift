import AppKit

/// Programmatic menu bar (no nib): app menu, Edit (so copy/paste work), and My AIM.
@MainActor
enum MainMenu {
    static func build(target: AnyObject) -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About AIM", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        item(appMenu, "Preferences…", #selector(AppDelegate.showPreferences(_:)), ",", target)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide AIM", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit AIM", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, title: "AIM", to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(edit, title: "Edit", to: main)

        let my = NSMenu(title: "My AIM")
        item(my, "Add Buddy…", #selector(AppDelegate.addBuddy(_:)), "n", target)
        item(my, "Change Screen Name…", #selector(AppDelegate.changeScreenName(_:)), "", target)
        item(my, "New Away Message…", #selector(AppDelegate.newAwayMessage(_:)), "", target)
        my.addItem(.separator())
        item(my, "Sign Off", #selector(AppDelegate.signOff(_:)), "", target)
        add(my, title: "My AIM", to: main)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(window, title: "Window", to: main)
        NSApp.windowsMenu = window

        return main
    }

    private static func add(_ menu: NSMenu, title: String, to main: NSMenu) {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.submenu = menu
        main.addItem(it)
    }

    private static func item(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String, _ target: AnyObject) {
        let it = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        it.target = target
    }
}
