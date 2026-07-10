import AppKit
import WorkspaceModel

// Dinamica dei menu, estratta dal corpo di `AppController` per tenerlo sul solo wiring: le voci
// del menu Workspace (azioni sulla selezione corrente, prima solo nel menu contestuale), i
// select-by-number del menu Go coi nomi reali, e la validazione enabled/disabled.

extension AppController {
    // MARK: - Menu Workspace (azioni sulla selezione corrente)

    @objc func regenerateSelectedWorkspaceName(_: Any?) {
        guard let workspace = store.selectedWorkspace else { return }
        store.markNameRegenerable(workspace.id)
    }

    @objc func toggleSelectedWorkspacePin(_: Any?) {
        guard let workspace = store.selectedWorkspace else { return }
        store.togglePin(workspace.id)
    }

    @objc func toggleSelectedWorkspaceArchive(_: Any?) {
        guard let workspace = store.selectedWorkspace else { return }
        store.toggleArchive(workspace.id)
    }

    @objc func toggleSelectedTabUnread(_: Any?) {
        guard let tab = store.selectedWorkspace?.selectedTab else { return }
        store.toggleUnread(tab.id)
    }

    @objc func moveSelectedTabToNewWorkspace(_: Any?) {
        guard let workspace = store.selectedWorkspace,
              let tab = workspace.selectedTab else { return }
        moveTabToNewWorkspace(tab, from: workspace)
    }

    @objc func moveSelectedWorkspaceToNewWindow(_: Any?) {
        guard let workspace = store.selectedWorkspace else { return }
        moveWorkspaceToNewWindow(workspace)
    }
}

// MARK: - Voci dinamiche (menuNeedsUpdate)

extension AppController: NSMenuDelegate {
    /// Aggiorna i menu che dipendono dallo stato all'apertura: il menu principale si ricostruisce
    /// solo al cambio keybinding, quindi tutto ciò che dipende dallo store va rinfrescato qui.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        switch menu.title {
        case "Go": updateGoMenu(menu)
        case "Workspace": updateWorkspaceMenu(menu)
        default: break
        }
    }

    /// Go: rimpiazza le voci numerate coi **nomi reali** di workspace (⌘1..9, ordine sidebar) e
    /// delle tab della strip del pane focused (⌥1..9). Solo le voci esistenti: niente no-op.
    private func updateGoMenu(_ menu: NSMenu) {
        let numbered: Set<Selector> = [
            #selector(AppController.selectWorkspaceByShortcut(_:)),
            #selector(AppController.selectTabByShortcut(_:)),
        ]
        // Butta le voci numerate del giro prima (e i loro separatori, marcati con tag -1).
        for item in menu.items where item.action.map(numbered.contains) == true || item.tag == -1 {
            menu.removeItem(item)
        }

        let workspaces = store.orderedWorkspaces.prefix(9)
        if !workspaces.isEmpty {
            menu.addItem(markedSeparator())
            for (index, workspace) in workspaces.enumerated() {
                menu.addItem(numberItem(
                    title: workspace.name,
                    action: #selector(AppController.selectWorkspaceByShortcut(_:)),
                    tag: index, key: "\(index + 1)", mask: [.command]
                ))
            }
        }
        let tabs = store.selectedWorkspace?.focusedPane.map { pane in
            pane.tabIDs.prefix(9).compactMap { store.selectedWorkspace?.tab($0) }
        } ?? []
        if !tabs.isEmpty {
            menu.addItem(markedSeparator())
            for (index, tab) in tabs.enumerated() {
                menu.addItem(numberItem(
                    title: tab.title,
                    action: #selector(AppController.selectTabByShortcut(_:)),
                    tag: index, key: "\(index + 1)", mask: [.option]
                ))
            }
        }
    }

    /// Workspace: i titoli dei toggle riflettono lo stato del workspace selezionato.
    private func updateWorkspaceMenu(_ menu: NSMenu) {
        guard let workspace = store.selectedWorkspace else { return }
        menu.item(withSelector: #selector(AppController.toggleSelectedWorkspacePin(_:)))?
            .title = workspace.pinned ? "Unpin" : "Pin"
        menu.item(withSelector: #selector(AppController.toggleSelectedWorkspaceArchive(_:)))?
            .title = workspace.archived ? "Unarchive" : "Archive"
        // Solo `unseen` è "unread" (segnale forte non visto): lì si offre "Mark as Read". Un
        // `pending` o un `none` si possono solo ri-alzare a forte. Stessa logica del contestuale.
        let isUnseen = workspace.selectedTab?.attention == .unseen
        menu.item(withSelector: #selector(AppController.toggleSelectedTabUnread(_:)))?
            .title = isUnseen ? "Mark as Read" : "Mark as Unread"
    }

    private func markedSeparator() -> NSMenuItem {
        let separator = NSMenuItem.separator()
        separator.tag = -1 // riconoscibile al prossimo update (i separatori non hanno action)
        return separator
    }

    private func numberItem(
        title: String, action: Selector, tag: Int, key: String, mask: NSEvent.ModifierFlags
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mask
        item.tag = tag
        item.target = self
        return item
    }
}

// MARK: - Enabled/disabled

extension AppController: NSMenuItemValidation {
    /// Con un overlay full-window aperto (dashboard/onboarding) il monitor si fa da parte: i
    /// `keyEquivalent` delle voci tornerebbero vivi ed eseguirebbero azioni sotto l'overlay.
    /// Qui si disabilita tutto tranne il toggle della dashboard (per chiuderla). A overlay chiuso,
    /// le voci si disabilitano solo dove l'azione sarebbe un no-op.
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if isDashboardOpen || isOnboardingOpen {
            let action = menuItem.representedObject as? ShortcutAction
            return isDashboardOpen && action == .toggleDashboard
        }
        if let action = menuItem.representedObject as? ShortcutAction {
            return isEnabled(action)
        }
        switch menuItem.action {
        case #selector(AppController.moveSelectedTabToNewWorkspace(_:)):
            return (store.selectedWorkspace?.tabs.count ?? 0) > 1
        case #selector(AppController.moveSelectedWorkspaceToNewWindow(_:)):
            guard let workspace = store.selectedWorkspace else { return false }
            return store.workspaces(in: workspace.windowID).count > 1
        case #selector(AppController.regenerateSelectedWorkspaceName(_:)),
             #selector(AppController.toggleSelectedWorkspacePin(_:)),
             #selector(AppController.toggleSelectedWorkspaceArchive(_:)):
            return store.selectedWorkspace != nil
        case #selector(AppController.toggleSelectedTabUnread(_:)):
            return store.selectedWorkspace?.selectedTab != nil
        default:
            return true
        }
    }

    private func isEnabled(_ action: ShortcutAction) -> Bool {
        switch action {
        case .closePane, .focusNextPane, .focusPrevPane:
            (store.selectedWorkspace?.layout.paneIDs.count ?? 0) > 1
        default:
            true
        }
    }
}

private extension NSMenu {
    func item(withSelector selector: Selector) -> NSMenuItem? {
        items.first { $0.action == selector }
    }
}
