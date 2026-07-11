import AppKit
import Core
import Panels
import WorkspaceModel

/// Handler di navigazione da menu, estratti dal corpo di `AppController` per tenerlo sul solo
/// wiring. I Cmd/Option + 1..9 passano dall'event monitor (`handleNavigationKey`), non da
/// keyEquivalent (gli shortcut con solo Option non fanno match in AppKit). Find/Clear/Jump non
/// stanno più qui: sono azioni rimappabili, eseguite via `ShortcutRuntime.perform(_:)`.
extension AppController {
    /// Cmd+1..9: seleziona il workspace all'indice nell'ordine della sidebar (`orderedWorkspaces`:
    /// pinned, poi con attenzione, poi il resto), non quello canonico. Così Cmd+1 apre sempre la
    /// riga in cima, anche quando un completamento la fa galleggiare su.
    @objc func selectWorkspaceByShortcut(_ sender: NSMenuItem) {
        let ordered = store.orderedWorkspaces
        guard sender.tag < ordered.count else { return }
        store.selectWorkspace(ordered[sender.tag].id)
    }

    /// Option+1..9: seleziona la tab all'indice **nella strip del pane focused** (tag 0-based).
    /// Col modello cmux le tab vivono nei pane: l'indice è quello che vedi nella strip.
    @objc func selectTabByShortcut(_ sender: NSMenuItem) {
        guard let workspace = store.selectedWorkspace,
              let pane = workspace.focusedPane,
              sender.tag < pane.tabIDs.count else { return }
        store.selectTab(pane.tabIDs[sender.tag], in: workspace)
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
            // pending), non lo spegne. Un click nella chrome (strip/sidebar) o un tasto altrove
            // è filtrato via da `owningPane`: cambiare tab non consuma più il marker. Risolvono
            // solo la ripresa vera (prompt -> running, via reducer), il dismiss o la chiusura:
            // "l'ho visto" non è "me ne sono occupato".
            // Con lo split si marca la tab del **pane colpito**, che può non essere il focused: un
            // click in un pane accanto dice che hai visto quella conversazione, non l'altra. E con
            // più finestre l'evento va chiesto a **quella da cui arriva**, non alla key: un click
            // in una finestra di sfondo la rende key solo dopo, e la key di adesso non lo possiede.
            let controller = windowController(for: event)
            if let controller, let hit = controller.splitVC.owningPane(of: event) {
                store.markSeen(hit.tabID)
                // Click-to-focus (convenzione universale dei terminali con split): un click dentro
                // il terminale di un pane gli dà anche il focus del model, così bordo, strip e
                // comandi (`Cmd+K`, find, split) seguono la tastiera, che AppKit ha già spostato
                // col first responder. Solo il click: un tasto arriva già al pane focused.
                let workspace = store.selectedWorkspace(in: controller.windowID)
                if event.type == .leftMouseDown, let workspace {
                    store.focusPane(hit.paneID, in: workspace)
                }
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

    /// La finestra da cui arriva l'evento. Il monitor è uno per app, ma con più finestre l'evento
    /// appartiene a quella sotto il puntatore o col focus di tastiera, che non è per forza la key.
    func windowController(for event: NSEvent) -> RelayWindowController? {
        guard let window = event.window else { return nil }
        return windowControllers.values.first { $0.window === window }
    }

    /// L'azione rimappata sulla combinazione dell'evento, se qualcuna la usa. La risoluzione è
    /// deterministica e privilegia gli override utente (`AppSettings.action(for:)`): un nuovo
    /// default shippato non deve rubare una combo scelta dall'utente, né cambiare esito a caso.
    private func shortcutAction(for event: NSEvent) -> ShortcutAction? {
        if event.optionGeneratedText != nil { return nil }
        guard let combo = KeyEventBridge.combo(from: event) else { return nil }
        return settings.action(for: combo)
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
        } else if let workspace = store.selectedWorkspace, let pane = workspace.focusedPane {
            // Option+N naviga la strip del pane focused: è l'indice che vedi a schermo.
            guard index < pane.tabIDs.count else { return true }
            store.selectTab(pane.tabIDs[index], in: workspace)
        }
        return true
    }
}

private extension NSEvent {
    var optionGeneratedText: String? {
        KeyboardTextInput.optionGeneratedText(
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifiers: .init(
                option: modifierFlags.contains(.option),
                shift: modifierFlags.contains(.shift),
                command: modifierFlags.contains(.command),
                control: modifierFlags.contains(.control)
            )
        )
    }
}
