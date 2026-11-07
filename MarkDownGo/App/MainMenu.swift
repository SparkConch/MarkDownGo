import AppKit

/// Menu bar built in code (no nib): the app is document based and every item targets the responder
/// chain, so `Document` / `EditorViewController` only have to implement the actions they support.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(appMenu())
        main.addItem(fileMenu())
        main.addItem(editMenu())
        main.addItem(viewMenu())
        main.addItem(windowMenu())
        return main
    }

    private static func submenu(_ titleKey: String) -> (NSMenuItem, NSMenu) {
        let item = NSMenuItem(title: L(titleKey), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: L(titleKey))
        item.submenu = menu
        return (item, menu)
    }

    private static func item(_ titleKey: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: L(titleKey), action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        return item
    }

    private static func appMenu() -> NSMenuItem {
        let (root, menu) = submenu("menu.app")
        menu.addItem(item("menu.about", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("menu.settings", #selector(AppDelegate.showSettings(_:)), ","))
        menu.addItem(.separator())
        let services = NSMenuItem(title: L("menu.services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(item("menu.hide", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("menu.hideOthers", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("menu.showAll", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("menu.quit", #selector(NSApplication.terminate(_:)), "q"))
        return root
    }

    private static func fileMenu() -> NSMenuItem {
        let (root, menu) = submenu("menu.file")
        let newItem = item("menu.new", #selector(NSDocumentController.newDocument(_:)), "n")
        newItem.target = NSDocumentController.shared
        let openItem = item("menu.open", #selector(NSDocumentController.openDocument(_:)), "o")
        openItem.target = NSDocumentController.shared
        menu.addItem(newItem)
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(item("menu.save", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("menu.revertToOpened", #selector(Document.revertToOpenedState(_:)), "r", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("menu.close", #selector(NSWindow.performClose(_:)), "w"))
        return root
    }

    private static func editMenu() -> NSMenuItem {
        let (root, menu) = submenu("menu.edit")
        menu.addItem(item("menu.undo", Selector(("undo:")))) 
        menu.addItem(item("menu.redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("menu.cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("menu.copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("menu.paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("menu.delete", #selector(NSText.delete(_:))))
        menu.addItem(.separator())
        menu.addItem(item("menu.selectAll", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        let (findRoot, find) = submenu("menu.find")
        // Tags follow NSTextView's find action raw values.
        find.addItem(item("menu.find.show", #selector(NSTextView.performFindPanelAction(_:)), "f", .command, tag: 1))
        find.addItem(item("menu.find.next", #selector(NSTextView.performFindPanelAction(_:)), "g", .command, tag: 2))
        find.addItem(item("menu.find.previous", #selector(NSTextView.performFindPanelAction(_:)), "g", [.command, .shift], tag: 3))
        menu.addItem(findRoot)
        return root
    }

    private static func viewMenu() -> NSMenuItem {
        let (root, menu) = submenu("menu.view")
        menu.addItem(item("menu.mode.source", #selector(EditorViewController.setModeSource(_:)), "1"))
        menu.addItem(item("menu.mode.split", #selector(EditorViewController.setModeSplit(_:)), "2"))
        menu.addItem(item("menu.mode.wysiwyg", #selector(EditorViewController.setModeWysiwyg(_:)), "3"))
        menu.addItem(.separator())
        menu.addItem(item("menu.outline", #selector(EditorViewController.toggleOutline(_:)), "0", [.command, .option]))
        return root
    }

    private static func windowMenu() -> NSMenuItem {
        let (root, menu) = submenu("menu.window")
        menu.addItem(item("menu.minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("menu.zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("menu.bringAllToFront", #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = menu
        return root
    }
}

/// Shorthand for a lookup that follows the in-app language setting and falls back to the key.
func L(_ key: String) -> String {
    Localization.string(key)
}
