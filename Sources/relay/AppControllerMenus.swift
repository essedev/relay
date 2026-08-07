import AppKit
import WorkspaceModel

// Dinamica dei menu, estratta dal corpo di `AppController` per tenerlo sul solo wiring: le voci
// del menu Workspace (azioni sulla selezione corrente, prima solo nel menu contestuale), i
// select-by-number del menu Go coi nomi reali, e la validazione enabled/disabled.

extension AppController {
    // MARK: - Menu Workspace (azioni sulla selezione corrente)

    @objc func regenerateSelectedWorkspaceName(_: Any?) {
        guard let workspace = store.selectedWorkspace else { return }
        regenerateWorkspaceName(workspace.id)
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

    /// Raggruppa il workspace selezionato: se è già in una card la scioglie (`Ungroup`, il
    /// gesto opposto e quello che serve dalla menu bar), altrimenti ne apre una nuova attorno a
    /// lui. Il nome è un placeholder: si rinomina dall'header della card.
    @objc func toggleSelectedWorkspaceGroup(_: Any?) {
        guard let workspace = store.selectedWorkspace else { return }
        if let groupID = workspace.groupID {
            store.ungroup(groupID)
        } else {
            store.createGroup(name: "New Group", with: [workspace.id])
        }
    }

    /// Tira il workspace selezionato fuori dalla sua card, lasciando la card agli altri membri.
    @objc func removeSelectedWorkspaceFromGroup(_: Any?) {
        guard let workspace = store.selectedWorkspace else { return }
        store.removeFromGroup(workspace.id)
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

        let workspaces = store.navigableWorkspaces.prefix(9)
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
        // Una riga libera apre una card, un membro la scioglie: una voce sola, come Pin/Unpin.
        // È un'azione rimappabile, quindi si cerca per `representedObject`, non per selector (il
        // suo action è `performShortcut`), e porta il keyEquivalent del binding corrente.
        menu.item(withAction: ShortcutAction.toggleGroup)?
            .title = workspace.groupID == nil ? "New Group with This" : "Ungroup"
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
    /// Con un overlay full-window aperto (dashboard/onboarding/guida) il monitor si fa da parte: i
    /// `keyEquivalent` delle voci tornerebbero vivi ed eseguirebbero azioni sotto l'overlay.
    /// Qui si disabilita tutto tranne le voci che **chiudono** l'overlay aperto. A overlay chiuso,
    /// le voci si disabilitano solo dove l'azione sarebbe un no-op.
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if isDashboardOpen || isOnboardingOpen || isGuideOpen {
            // La guida non è un'azione rimappabile: la sua voce si riconosce dal selector.
            if isGuideOpen, menuItem.action == #selector(AppController.showGuide(_:)) {
                return true
            }
            let action = menuItem.representedObject as? ShortcutAction
            return isDashboardOpen && action == .toggleDashboard
        }
        if let action = menuItem.representedObject as? ShortcutAction {
            return isEnabled(action)
        }
        return isEnabled(selector: menuItem.action)
    }

    /// Voci del menu Workspace (selector diretti, non azioni rimappabili): abilitate solo dove
    /// l'azione farebbe davvero qualcosa.
    private func isEnabled(selector: Selector?) -> Bool {
        switch selector {
        case #selector(AppController.moveSelectedTabToNewWorkspace(_:)):
            return (store.selectedWorkspace?.tabs.count ?? 0) > 1
        case #selector(AppController.moveSelectedWorkspaceToNewWindow(_:)):
            guard let workspace = store.selectedWorkspace else { return false }
            return store.workspaces(in: workspace.windowID).count > 1
        case #selector(AppController.regenerateSelectedWorkspaceName(_:)),
             #selector(AppController.toggleSelectedWorkspaceArchive(_:)),
             #selector(AppController.toggleSelectedWorkspaceGroup(_:)):
            return store.selectedWorkspace != nil
        case #selector(AppController.toggleSelectedWorkspacePin(_:)):
            // Dentro una card il pin è del gruppo, non della riga: la voce sarebbe un no-op.
            guard let workspace = store.selectedWorkspace else { return false }
            return workspace.groupID == nil
        case #selector(AppController.removeSelectedWorkspaceFromGroup(_:)):
            return store.selectedWorkspace?.groupID != nil
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

    func item(withAction action: ShortcutAction) -> NSMenuItem? {
        items.first { ($0.representedObject as? ShortcutAction) == action }
    }
}
