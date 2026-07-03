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

    // MARK: - Monitor tastiera/mouse

    /// Un solo monitor locale per: (1) navigazione Cmd/Option + 1..9 - gli shortcut menu con solo
    /// Option non fanno match (AppKit confronta il carattere trasformato, es. Option+1 = "¡"); (2)
    /// mark-read - tasto o click mentre l'app è attiva "usano" la tab in vista e spengono il marker
    /// di completamento (la visita reale, non il semplice ritorno in foreground). Non filtro il
    /// click all'area del terminale: risalire al frame non vale la complessità, e interagire con
    /// l'app col completamento in vista vale comunque come "visto".
    func installNavigationKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, handleNavigationKey(event) {
                return nil // shortcut di navigazione consumato
            }
            if let tab = store.selectedWorkspace?.selectedTab, tab.attention {
                tab.attention = false
            }
            return event
        }
    }

    func handleNavigationKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == .option else { return false }
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
              let digit = Int(chars), (1 ... 9).contains(digit) else { return false }
        let index = digit - 1

        if flags == .command {
            // Ordine della sidebar (con float dei completati/attenzione), non quello canonico:
            // Cmd+N segue la posizione visiva della riga.
            let ordered = store.orderedWorkspaces
            if index < ordered.count {
                store.selectWorkspace(ordered[index].id)
            }
        } else if let workspace = store.selectedWorkspace, index < workspace.tabs.count {
            store.selectTab(workspace.tabs[index].id, in: workspace)
        }
        return true
    }
}
