import AppKit
import WorkspaceModel

/// Costruisce il menu principale. Le azioni rimappabili sono voci `performShortcut` con la combo
/// (dai keybinding) mostrata nel titolo: l'hotkey vero lo gestisce il monitor in
/// `AppControllerNavigation`, non il `keyEquivalent` (che non gestisce tutte le combo). Restano
/// fisse col loro `keyEquivalent` solo Copy/Paste/Select All (responder), Quit e Settings.
@MainActor
enum MainMenuBuilder {
    static func build(target: AnyObject, settings: AppSettings) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenu(target))
        mainMenu.addItem(fileMenu(target, settings))
        mainMenu.addItem(goMenu(target, settings))
        mainMenu.addItem(viewMenu(target, settings))
        mainMenu.addItem(editMenu(target, settings))
        return mainMenu
    }

    // MARK: - Voci

    /// Voce di un'azione rimappabile: clic -> `performShortcut`, combo nel titolo, l'hotkey al
    /// monitor. `keyEquivalent` vuoto per non fare doppio trigger con il monitor.
    private static func actionItem(
        _ action: ShortcutAction,
        _ settings: AppSettings,
        _ target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: "\(action.label)   \(settings.binding(for: action).display)",
            action: #selector(AppController.performShortcut(_:)),
            keyEquivalent: ""
        )
        item.representedObject = action
        item.target = target
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem()
        let menu = NSMenu(title: title)
        for sub in items {
            menu.addItem(sub)
        }
        item.submenu = menu
        return item
    }

    // MARK: - Menu

    private static func appMenu(_ target: AnyObject) -> NSMenuItem {
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(AppController.openSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = target
        let quit = NSMenuItem(
            title: "Quit Relay",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        return submenu("Relay", [settingsItem, .separator(), quit])
    }

    private static func fileMenu(_ target: AnyObject, _ settings: AppSettings) -> NSMenuItem {
        submenu("File", [
            actionItem(.newWorkspace, settings, target),
            actionItem(.newTab, settings, target),
            actionItem(.openFolder, settings, target),
            .separator(),
            actionItem(.closeTab, settings, target),
            actionItem(.closeWorkspace, settings, target),
        ])
    }

    /// Go: attenzione, cicli tab/workspace, poi i select-by-number (fissi, gestiti dal monitor: il
    /// titolo porta l'hint della combo).
    private static func goMenu(_ target: AnyObject, _ settings: AppSettings) -> NSMenuItem {
        var items: [NSMenuItem] = [
            actionItem(.toggleDashboard, settings, target),
            actionItem(.nextAttention, settings, target),
            actionItem(.prevAttention, settings, target),
            .separator(),
            actionItem(.cycleTabForward, settings, target),
            actionItem(.cycleTabBackward, settings, target),
            actionItem(.cycleWorkspaceForward, settings, target),
            actionItem(.cycleWorkspaceBackward, settings, target),
            .separator(),
        ]
        for index in 1 ... 9 {
            items.append(numberItem(
                "Workspace \(index)   ⌘\(index)",
                #selector(AppController.selectWorkspaceByShortcut(_:)),
                index - 1,
                target
            ))
        }
        items.append(.separator())
        for index in 1 ... 9 {
            items.append(numberItem(
                "Tab \(index)   ⌥\(index)",
                #selector(AppController.selectTabByShortcut(_:)),
                index - 1,
                target
            ))
        }
        return submenu("Go", items)
    }

    private static func numberItem(
        _ title: String,
        _ action: Selector,
        _ tag: Int,
        _ target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.tag = tag
        item.target = target
        return item
    }

    private static func viewMenu(_ target: AnyObject, _ settings: AppSettings) -> NSMenuItem {
        submenu("View", [
            actionItem(.toggleSidebar, settings, target),
            .separator(),
            actionItem(.zoomIn, settings, target),
            actionItem(.zoomOut, settings, target),
            actionItem(.actualSize, settings, target),
        ])
    }

    /// Edit: Copy/Paste/Select All restano `keyEquivalent` (responder chain di SwiftTerm); find e
    /// clear sono azioni rimappabili.
    private static func editMenu(_ target: AnyObject, _ settings: AppSettings) -> NSMenuItem {
        let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let paste = NSMenuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        let selectAll = NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        return submenu("Edit", [
            copy, paste, selectAll,
            .separator(),
            actionItem(.find, settings, target),
            actionItem(.findNext, settings, target),
            actionItem(.findPrevious, settings, target),
            actionItem(.clear, settings, target),
        ])
    }
}
