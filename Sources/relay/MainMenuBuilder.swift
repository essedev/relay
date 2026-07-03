import AppKit

/// Costruisce il menu principale. Le azioni sono selector sul target (AppController): qui c'è solo
/// la struttura, così il controller resta wiring.
@MainActor
enum MainMenuBuilder {
    static func build(target: AnyObject) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeAppMenuItem(target: target))
        mainMenu.addItem(makeFileMenuItem(target: target))
        mainMenu.addItem(makeGoMenuItem(target: target))
        mainMenu.addItem(makeViewMenuItem(target: target))
        mainMenu.addItem(makeEditMenuItem(target: target))
        return mainMenu
    }

    private static func makeAppMenuItem(target: AnyObject) -> NSMenuItem {
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        addItem(to: appMenu, "Settings…", #selector(AppController.openSettings(_:)), ",", target)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Relay",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return appItem
    }

    private static func makeFileMenuItem(target: AnyObject) -> NSMenuItem {
        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        addItem(
            to: fileMenu,
            "New Workspace",
            #selector(AppController.newWorkspace(_:)),
            "n",
            target
        )
        addItem(to: fileMenu, "New Tab", #selector(AppController.newTab(_:)), "t", target)
        addItem(
            to: fileMenu,
            "Open Folder as Workspace…",
            #selector(AppController.openFolderAsWorkspace(_:)),
            "o",
            target
        )
        fileMenu.addItem(.separator())
        addItem(
            to: fileMenu,
            "Close Tab",
            #selector(AppController.closeCurrentTab(_:)),
            "w",
            target
        )
        return fileItem
    }

    /// Menu "Go": Cmd+1..9 per i workspace, Option+1..9 per le tab (i due assi, stile cmux).
    /// Nessun keyEquivalent: gli shortcut sono gestiti dall'event monitor in AppController (i menu
    /// con solo Option non fanno match); le voci restano cliccabili, con hint nel titolo.
    private static func makeGoMenuItem(target: AnyObject) -> NSMenuItem {
        let goItem = NSMenuItem()
        let goMenu = NSMenu(title: "Go")
        goItem.submenu = goMenu

        // Cmd+J (keyEquivalent vero: Cmd+lettera fa match, a differenza di Option+cifra).
        addItem(
            to: goMenu,
            "Next Attention",
            #selector(AppController.jumpToAttention(_:)),
            "j",
            target
        )
        goMenu.addItem(.separator())

        for index in 1 ... 9 {
            let item = NSMenuItem(
                title: "Workspace \(index)  (⌘\(index))",
                action: #selector(AppController.selectWorkspaceByShortcut(_:)),
                keyEquivalent: ""
            )
            item.tag = index - 1
            item.target = target
            goMenu.addItem(item)
        }
        goMenu.addItem(.separator())
        for index in 1 ... 9 {
            let item = NSMenuItem(
                title: "Tab \(index)  (⌥\(index))",
                action: #selector(AppController.selectTabByShortcut(_:)),
                keyEquivalent: ""
            )
            item.tag = index - 1
            item.target = target
            goMenu.addItem(item)
        }
        return goItem
    }

    private static func makeViewMenuItem(target: AnyObject) -> NSMenuItem {
        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        addItem(
            to: viewMenu,
            "Toggle Sidebar",
            #selector(AppController.toggleSidebar(_:)),
            "b",
            target
        )
        viewMenu.addItem(.separator())
        addItem(to: viewMenu, "Zoom In", #selector(AppController.zoomIn(_:)), "=", target)
        addItem(to: viewMenu, "Zoom Out", #selector(AppController.zoomOut(_:)), "-", target)
        addItem(to: viewMenu, "Actual Size", #selector(AppController.resetZoom(_:)), "0", target)
        return viewItem
    }

    private static func makeEditMenuItem(target: AnyObject) -> NSMenuItem {
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenu.addItem(.separator())
        // Target esplicito (non responder chain): Cmd+F/Cmd+K funzionano anche col terminale in
        // focus, intercettati prima che l'evento arrivi al pty.
        addItem(to: editMenu, "Find…", #selector(AppController.performFind(_:)), "f", target)
        addItem(
            to: editMenu,
            "Clear to Start",
            #selector(AppController.clearTerminal(_:)),
            "k",
            target
        )
        return editItem
    }

    private static func addItem(
        to menu: NSMenu,
        _ title: String,
        _ action: Selector,
        _ key: String,
        _ target: AnyObject
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        menu.addItem(item)
    }
}
