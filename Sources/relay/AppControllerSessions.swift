import AppKit
import WorkspaceModel

/// Disattivazione delle sessioni agente: spegne il processo tenendo il `ResumeBinding`, così la
/// tab resta dov'è e ci torni dalla barra di resume. Estratto dal corpo di `AppController` come
/// `AppControllerClose`: lì c'è la policy della chiusura, qui quella dello spegnimento.
///
/// Il motivo è la memoria: una surface idle costa 0,3-0,5 MB, una sessione agente ~200 MB più una
/// decina di processi (server MCP compresi). Il cap LRU non tocca le tab con un agente vivo, per
/// scelta, quindi con decine di sessioni la memoria è tutta lì. Numeri in `docs/research/PERF.md`.
///
/// Ordine obbligato: prima si marca la tab nello store, poi si butta la surface. Uccidere
/// l'agente fa scattare il suo `SessionEnd`, che su una tab normale azzera il `resume`: se la
/// marcatura arrivasse dopo, l'evento troverebbe la tab ancora normale e butterebbe via proprio
/// il binding che serve a tornare indietro.
extension AppController {
    /// Voce di menu bar: agisce sul workspace mostrato dalla finestra key.
    @objc func deactivateSelectedWorkspaceSessions(_: Any?) {
        guard let workspace = store.selectedWorkspace else { return }
        requestDeactivateWorkspace(workspace)
    }

    /// Spegne la sessione di una tab (menu contestuale della strip).
    func requestDeactivateTab(_ tab: WorkspaceModel.Tab) {
        guard tab.deactivationBlock(isOnScreen: store.isMounted(tab.id)) == nil else { return }
        deactivate([tab.id])
    }

    /// Spegne tutte le sessioni disattivabili di un workspace. È l'azione che serve davvero:
    /// una per tab imporrebbe decine di decisioni identiche.
    func requestDeactivateWorkspace(_ workspace: Workspace) {
        var eligible: [WorkspaceModel.Tab] = []
        var blocked: [DeactivationBlock: Int] = [:]
        for tab in workspace.tabs {
            if let block = tab.deactivationBlock(isOnScreen: store.isMounted(tab.id)) {
                blocked[block, default: 0] += 1
            } else {
                eligible.append(tab)
            }
        }
        guard !eligible.isEmpty else {
            presentNothingToDeactivate(in: workspace, blocked: blocked)
            return
        }
        let ids = eligible.map(\.id)
        confirmDeactivation(
            count: ids.count,
            blocked: blocked,
            in: workspace
        ) { [weak self] in
            self?.deactivate(ids)
        }
    }

    /// Marca le tab e butta le loro surface. La surface rinasce al prossimo focus (shell fresca
    /// nella cwd salvata), e la barra di resume rimette in piedi la sessione.
    private func deactivate(_ tabIDs: [WorkspaceModel.Tab.ID]) {
        let done = store.deactivate(Set(tabIDs))
        for tabID in done {
            registry.release(tabID)
        }
        log.info("deactivated \(done.count) session(s)")
    }

    /// Conferma con la conta di cosa si spegne e di cosa resta fuori. Una disattivazione è
    /// reversibile (il binding resta) ma interrompe comunque le sessioni: dire solo "3 tab" senza
    /// dire perché le altre no trasformerebbe l'azione in una scommessa.
    private func confirmDeactivation(
        count: Int,
        blocked: [DeactivationBlock: Int],
        in workspace: Workspace,
        onConfirm: @escaping () -> Void
    ) {
        guard let target = windowControllers[workspace.windowID]?.window ?? window else {
            onConfirm()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = count == 1
            ? "Deactivate 1 session in \u{201C}\(workspace.name)\u{201D}?"
            : "Deactivate \(count) sessions in \u{201C}\(workspace.name)\u{201D}?"
        alert.informativeText = Self.deactivationInfo(count: count, blocked: blocked)
        let deactivateButton = alert.addButton(withTitle: "Deactivate")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        deactivateButton.keyEquivalent = "" // Invio non deve spegnere per errore
        cancelButton.keyEquivalent = "\r"
        alert.beginSheetModal(for: target) { response in
            if response == .alertFirstButtonReturn { onConfirm() }
        }
    }

    /// Nessuna tab disattivabile: un'azione che non fa niente e non dice niente è
    /// indistinguibile da un bug (stessa regola della nomina manuale).
    private func presentNothingToDeactivate(
        in workspace: Workspace,
        blocked: [DeactivationBlock: Int]
    ) {
        guard let target = windowControllers[workspace.windowID]?.window ?? window else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Nothing to deactivate in \u{201C}\(workspace.name)\u{201D}"
        alert.informativeText = blocked.isEmpty
            ? "This workspace has no agent sessions."
            : Self.blockedSummary(blocked)
        alert.beginSheetModal(for: target, completionHandler: nil)
    }

    static func deactivationInfo(count: Int, blocked: [DeactivationBlock: Int]) -> String {
        let head = count == 1
            ? "The session stops and its processes are terminated. The tab stays where it is, "
            + "and reopening it offers to resume."
            : "The sessions stop and their processes are terminated. The tabs stay where they "
            + "are, and reopening one offers to resume."
        guard !blocked.isEmpty else { return head }
        return head + "\n\n" + blockedSummary(blocked)
    }

    static func blockedSummary(_ blocked: [DeactivationBlock: Int]) -> String {
        // Ordine fisso (non quello del dizionario): la stessa situazione deve leggersi sempre
        // uguale.
        let lines = DeactivationBlock.allCases.compactMap { block -> String? in
            guard let count = blocked[block], count > 0 else { return nil }
            let tabs = count == 1 ? "1 tab" : "\(count) tabs"
            return switch block {
            case .onScreen: "\(tabs) left alone: on screen."
            case .working: "\(tabs) left alone: an agent is working."
            case .noSession: "\(tabs) left alone: no session to come back to."
            }
        }
        return lines.joined(separator: "\n")
    }
}
