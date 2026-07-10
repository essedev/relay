import AppKit
import WorkspaceModel

/// Costruisce il menu principale, nell'ordine HIG: Relay, File, Edit, View, [Workspace, Pane, Go],
/// Window, Help. Le azioni rimappabili sono voci `performShortcut` col `keyEquivalent` **vero**
/// della combo corrente: la colonna delle scorciatoie è quella nativa, ma l'hotkey lo esegue
/// comunque il monitor (`AppControllerNavigation`), che consuma l'evento **prima** che arrivi al
/// menu - niente doppio trigger. Il keyEquivalent scatterebbe solo quando il monitor si fa da
/// parte (dashboard/onboarding aperti), ed è lì che `validateMenuItem` disabilita le voci.
/// Il recorder consuma tutto durante la registrazione, quindi non passa di qui.
@MainActor
enum MainMenuBuilder {
    static func build(target: AnyObject, settings: AppSettings) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenu(target))
        mainMenu.addItem(fileMenu(target, settings))
        mainMenu.addItem(editMenu(target, settings))
        mainMenu.addItem(viewMenu(target, settings))
        mainMenu.addItem(workspaceMenu(target, settings))
        mainMenu.addItem(paneMenu(target, settings))
        mainMenu.addItem(goMenu(target, settings))
        mainMenu.addItem(windowMenu(target))
        mainMenu.addItem(helpMenu(target))
        return mainMenu
    }

    // MARK: - Voci

    /// Voce di un'azione rimappabile: clic -> `performShortcut`, combo come `keyEquivalent`
    /// (colonna nativa; il trigger vero resta il monitor, vedi sopra).
    private static func actionItem(
        _ action: ShortcutAction,
        _ settings: AppSettings,
        _ target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: action.label,
            action: #selector(AppController.performShortcut(_:)),
            keyEquivalent: ""
        )
        item.representedObject = action
        item.target = target
        applyKeyEquivalent(settings.binding(for: action), to: item)
        return item
    }

    /// Converte una `KeyCombo` nel `keyEquivalent` AppKit (carattere + maschera). I tasti speciali
    /// usano i function key di AppKit; l'uppercase resta minuscolo (lo Shift sta nella maschera).
    private static func applyKeyEquivalent(_ combo: KeyCombo, to item: NSMenuItem) {
        item.keyEquivalent = keyEquivalentCharacter(for: combo.key)
        var mask: NSEvent.ModifierFlags = []
        if combo.modifiers.contains(.command) { mask.insert(.command) }
        if combo.modifiers.contains(.shift) { mask.insert(.shift) }
        if combo.modifiers.contains(.option) { mask.insert(.option) }
        if combo.modifiers.contains(.control) { mask.insert(.control) }
        item.keyEquivalentModifierMask = mask
    }

    private static func keyEquivalentCharacter(for key: String) -> String {
        switch key {
        case "tab": "\t"
        case "return": "\r"
        case "escape": "\u{1B}"
        case "space": " "
        case "delete": "\u{08}"
        case "up": arrow(NSUpArrowFunctionKey)
        case "down": arrow(NSDownArrowFunctionKey)
        case "left": arrow(NSLeftArrowFunctionKey)
        case "right": arrow(NSRightArrowFunctionKey)
        default: key
        }
    }

    /// I function key delle frecce sono costanti AppKit sicure, ma `UnicodeScalar(Int)` resta
    /// failable: il fallback (nessun keyEquivalent) è solo per il tipo.
    private static func arrow(_ functionKey: Int) -> String {
        UnicodeScalar(functionKey).map { String($0) } ?? ""
    }

    private static func item(
        _ title: String,
        _ action: Selector?,
        _ target: AnyObject?,
        key: String = "",
        mask: NSEvent.ModifierFlags = [.command]
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : mask
        item.target = target
        return item
    }

    private static func submenu(
        _ title: String, _ items: [NSMenuItem], delegate: NSMenuDelegate? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: title)
        menu.delegate = delegate
        for sub in items {
            menu.addItem(sub)
        }
        item.submenu = menu
        return item
    }

    // MARK: - Menu

    private static func appMenu(_ target: AnyObject) -> NSMenuItem {
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu

        let hideOthers = item(
            "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), nil,
            key: "h", mask: [.command, .option]
        )
        return submenu("Relay", [
            item("About Relay", #selector(AppController.showAbout(_:)), target),
            item("Check for Updates…", #selector(AppController.checkForUpdates(_:)), target),
            .separator(),
            item("Settings…", #selector(AppController.openSettings(_:)), target, key: ","),
            .separator(),
            services,
            .separator(),
            item("Hide Relay", #selector(NSApplication.hide(_:)), nil, key: "h"),
            hideOthers,
            item("Show All", #selector(NSApplication.unhideAllApplications(_:)), nil),
            .separator(),
            item("Quit Relay", #selector(NSApplication.terminate(_:)), nil, key: "q"),
        ])
    }

    private static func fileMenu(_ target: AnyObject, _ settings: AppSettings) -> NSMenuItem {
        submenu("File", [
            actionItem(.newTab, settings, target),
            actionItem(.newWorkspace, settings, target),
            actionItem(.newWindow, settings, target),
            actionItem(.openFolder, settings, target),
            .separator(),
            actionItem(.closeTab, settings, target),
            actionItem(.closeWorkspace, settings, target),
            actionItem(.closeWindow, settings, target),
        ])
    }

    /// Edit: Copy/Paste/Select All restano `keyEquivalent` fissi (responder chain di SwiftTerm);
    /// find raggruppato in un sottomenu come Terminal.app.
    private static func editMenu(_ target: AnyObject, _ settings: AppSettings) -> NSMenuItem {
        let copy = item("Copy", #selector(NSText.copy(_:)), nil, key: "c")
        let paste = item("Paste", #selector(NSText.paste(_:)), nil, key: "v")
        let selectAll = item("Select All", #selector(NSText.selectAll(_:)), nil, key: "a")
        let find = submenu("Find", [
            actionItem(.find, settings, target),
            actionItem(.findNext, settings, target),
            actionItem(.findPrevious, settings, target),
        ])
        find.title = "Find"
        return submenu("Edit", [
            copy, paste, selectAll,
            .separator(),
            find,
            .separator(),
            actionItem(.clear, settings, target),
        ])
    }

    private static func viewMenu(_ target: AnyObject, _ settings: AppSettings) -> NSMenuItem {
        let fullScreen = item(
            "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), nil,
            key: "f", mask: [.command, .control]
        )
        return submenu("View", [
            actionItem(.toggleSidebar, settings, target),
            .separator(),
            actionItem(.zoomIn, settings, target),
            actionItem(.zoomOut, settings, target),
            actionItem(.actualSize, settings, target),
            .separator(),
            item("Runtime Stats", #selector(AppController.showRuntimeStats(_:)), target),
            .separator(),
            fullScreen,
        ])
    }

    /// Workspace: le azioni sul workspace selezionato che prima vivevano solo nel menu
    /// contestuale della sidebar (scopribilità zero). I titoli dei toggle (Pin/Unpin,
    /// Archive/Unarchive, Read/Unread) si aggiornano all'apertura (`menuNeedsUpdate` in
    /// `AppControllerMenus`, riconosciuto dal titolo del menu).
    private static func workspaceMenu(_ target: AnyObject, _: AppSettings) -> NSMenuItem {
        submenu("Workspace", [
            item(
                "Regenerate Name",
                #selector(AppController.regenerateSelectedWorkspaceName(_:)), target
            ),
            .separator(),
            item("Pin", #selector(AppController.toggleSelectedWorkspacePin(_:)), target),
            item("Archive", #selector(AppController.toggleSelectedWorkspaceArchive(_:)), target),
            item("Mark as Read", #selector(AppController.toggleSelectedTabUnread(_:)), target),
            .separator(),
            item(
                "Move Tab to New Workspace",
                #selector(AppController.moveSelectedTabToNewWorkspace(_:)), target
            ),
            item(
                "Move Workspace to New Window",
                #selector(AppController.moveSelectedWorkspaceToNewWindow(_:)), target
            ),
        ], delegate: target as? NSMenuDelegate)
    }

    /// Pane: dividere l'area, muovere il focus fra i pane, chiuderne uno (con le sue tab).
    private static func paneMenu(_ target: AnyObject, _ settings: AppSettings) -> NSMenuItem {
        submenu("Pane", [
            actionItem(.splitRight, settings, target),
            actionItem(.splitDown, settings, target),
            .separator(),
            actionItem(.focusNextPane, settings, target),
            actionItem(.focusPrevPane, settings, target),
            .separator(),
            actionItem(.closePane, settings, target),
        ])
    }

    /// Go: attenzione, cicli tab/workspace, poi i select-by-number coi **nomi reali** di workspace
    /// e tab, ripopolati all'apertura (`menuNeedsUpdate`): il menu si ricostruisce solo al cambio
    /// keybinding, quindi i nomi non possono essere statici.
    private static func goMenu(_ target: AnyObject, _ settings: AppSettings) -> NSMenuItem {
        submenu("Go", [
            actionItem(.toggleDashboard, settings, target),
            actionItem(.nextAttention, settings, target),
            actionItem(.prevAttention, settings, target),
            .separator(),
            actionItem(.cycleTabForward, settings, target),
            actionItem(.cycleTabBackward, settings, target),
            actionItem(.cycleWorkspaceForward, settings, target),
            actionItem(.cycleWorkspaceBackward, settings, target),
            // Le voci numerate (workspace ⌘1..9, tab ⌥1..9) arrivano da `menuNeedsUpdate`.
        ], delegate: target as? NSMenuDelegate)
    }

    /// Window: le voci standard di sistema. Registrato come `NSApp.windowsMenu`: AppKit ci
    /// appende da solo la lista delle finestre aperte.
    private static func windowMenu(_: AnyObject) -> NSMenuItem {
        let minimize = item("Minimize", #selector(NSWindow.performMiniaturize(_:)), nil, key: "m")
        let zoom = item("Zoom", #selector(NSWindow.performZoom(_:)), nil)
        let front = item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), nil)
        let menuItem = submenu("Window", [minimize, zoom, .separator(), front])
        NSApp.windowsMenu = menuItem.submenu
        return menuItem
    }

    /// Help: riapre l'onboarding (Welcome to Relay). Registrato come `NSApp.helpMenu`: AppKit ci
    /// mette il campo di ricerca standard.
    private static func helpMenu(_ target: AnyObject) -> NSMenuItem {
        let menuItem = submenu("Help", [
            item("Welcome to Relay", #selector(AppController.showWelcome(_:)), target),
        ])
        NSApp.helpMenu = menuItem.submenu
        return menuItem
    }
}
