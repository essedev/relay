import AppKit
import WorkspaceModel

/// Handler di navigazione da menu (Cmd/Option + 1..9), estratti dal corpo di `AppController` per
/// tenerlo sul solo wiring. Gli shortcut da tastiera veri passano dall'event monitor
/// (`handleNavigationKey`); queste sono le voci cliccabili del menu "Go".
extension AppController {
    /// Cmd+1..9: seleziona il workspace all'indice nell'ordine della sidebar (`orderedWorkspaces`:
    /// pinned, poi con attenzione, poi il resto), non quello canonico. Così Cmd+1 apre sempre la
    /// riga in cima, anche quando un completamento la fa galleggiare su.
    @objc func selectWorkspaceByShortcut(_ sender: NSMenuItem) {
        let ordered = store.orderedWorkspaces
        guard sender.tag < ordered.count else { return }
        store.selectWorkspace(ordered[sender.tag].id)
    }

    /// Option+1..9: seleziona la tab all'indice nel workspace corrente (tag 0-based).
    @objc func selectTabByShortcut(_ sender: NSMenuItem) {
        guard let workspace = store.selectedWorkspace,
              sender.tag < workspace.tabs.count else { return }
        store.selectTab(workspace.tabs[sender.tag].id, in: workspace)
    }
}
