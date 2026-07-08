import AppKit
import Panels
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
    /// mark-read - interazione *col terminale* in vista (tasto col terminale in focus, o click
    /// dentro la sua view: `splitVC.terminalOwns`) che declassa il marker di completamento. Il
    /// filtro all'area del terminale è voluto: un click di navigazione nella chrome (cambio tab
    /// nella tab bar, cambio workspace nella sidebar) o un tasto in un campo di rename non è
    /// "occuparsi della conversazione", quindi non consuma il segnale.
    func installNavigationKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            // Mentre il recorder registra, il monitor è trasparente: l'evento arriva al recorder.
            if settings.isCapturingShortcut { return event }
            // Onboarding aperto: i tasti vanno alla vista (frecce, Invio, Esc, gestiti da lei);
            // nav 1..9, azioni rimappabili e mark-read sospesi, come per la dashboard.
            if isOnboardingOpen { return event }
            // Dashboard aperta: i tasti vanno alla vista (filtro, frecce, Invio; Esc lo gestisce
            // lei). Resta attivo solo il toggle per chiuderla; niente nav 1..9 e niente mark-read
            // (stai facendo triage, non usando la tab sotto l'overlay).
            if isDashboardOpen {
                let action = event.type == .keyDown ? shortcutAction(for: event) : nil
                if action == .toggleDashboard {
                    perform(.toggleDashboard)
                    return nil
                }
                return event
            }
            if event.type == .keyDown {
                if handleNavigationKey(event) { return nil } // select 1..9 (fissi)
                if let action = shortcutAction(for: event) {
                    perform(action)
                    return nil // hotkey rimappabile consumato
                }
            }
            // Interazione col terminale in vista (tasto col terminale in focus, o click dentro la
            // sua view) = la percezione declassa il completamento da forte a quieto (unseen ->
            // pending), non lo spegne. Un click nella chrome (tab bar/sidebar) o un tasto altrove
            // è filtrato via da `terminalOwns`: cambiare tab non consuma più il marker. Risolvono
            // solo la ripresa vera (prompt -> running, via reducer), il dismiss o la chiusura:
            // "l'ho visto" non è "me ne sono occupato".
            if splitVC?.terminalOwns(event) == true {
                store.selectedWorkspace?.selectedTab?.markSeen()
            }
            return event
        }
    }

    /// Durata del "flash" di completamento sulla tab in vista: il marker nasce forte (ring verde +
    /// flash + badge pieno) e dopo questo intervallo si declassa a "in sospeso" (badge dimesso).
    private static let completionFlashDuration: TimeInterval = 4

    /// Schedula il mark-read differito per un completamento avvenuto sulla tab in vista (segnalato
    /// da `store.onVisibleCompletion`): dopo `completionFlashDuration` declassa `unseen` ->
    /// `pending` (`store.markSeen`, no-op se nel frattempo hai interagito, ripreso o dismesso).
    /// Rimpiazza un timer già pendente sulla stessa tab, così un nuovo completamento riparte con un
    /// flash pieno. Sta qui, accanto al mark-read da interazione: è la sua variante automatica.
    func scheduleCompletionFlashDecay(for tabID: UUID) {
        completionFlashTimers[tabID]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.completionFlashTimers[tabID] = nil
            self?.store.markSeen(tabID)
        }
        completionFlashTimers[tabID] = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.completionFlashDuration, execute: work
        )
    }

    /// L'azione rimappata sulla combinazione dell'evento, se qualcuna la usa.
    private func shortcutAction(for event: NSEvent) -> ShortcutAction? {
        guard let combo = KeyEventBridge.combo(from: event) else { return nil }
        return settings.keybindings.first { $0.value == combo }?.key
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
