import AppKit
import WorkspaceModel

/// Handler di navigazione e comandi terminale da menu, estratti dal corpo di `AppController` per
/// tenerlo sul solo wiring. I Cmd/Option + 1..9 passano dall'event monitor (`handleNavigationKey`);
/// Cmd+F/Cmd+K/Cmd+J sono keyEquivalent veri (menu), che funzionano anche col terminale in focus.
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

    /// Cmd+F: apre/chiude la ricerca nel terminale attivo.
    @objc func performFind(_: Any?) {
        splitVC.toggleFind()
    }

    /// Cmd+K: pulisce il terminale attivo (scrollback + schermo, prompt ridisegnato).
    @objc func clearTerminal(_: Any?) {
        splitVC.clearActiveTerminal()
    }

    /// Cmd+J: salta alla prossima tab che richiede attenzione (input o completamento non visto).
    @objc func jumpToAttention(_: Any?) {
        store.focusNextAttention()
    }
}
