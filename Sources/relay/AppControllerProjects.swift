import AppKit
import Core
import Panels
import WorkspaceModel

/// Progetti e pagine: aprire e chiudere progetti dalle pagine Home e Projects, e passare da una
/// pagina all'altra. Estratto dal corpo di `AppController` come le altre aree: qui c'è il wiring,
/// le decisioni stanno nello store (`setClosed`, `openProject`) e nei modelli delle pagine.
extension AppController {
    /// Le azioni delle pagine di una finestra.
    func makePageActions() -> PageActions {
        PageActions(
            openSession: { [weak self] workspace, tab in
                self?.store.reveal(workspaceID: workspace.id, tabID: tab.id)
                self?.keyWindowController?.activate()
            },
            openProject: { [weak self] workspace in self?.openProject(workspace) },
            closeProject: { [weak self] workspace in self?.requestCloseProject(workspace) },
            closeProjects: { [weak self] projects in self?.requestCloseProjects(projects) },
            newProject: { [weak self] in self?.newWorkspace(nil) },
            peek: { [weak self] tabID in self?.peek(tabID) }
        )
    }

    /// Riapre (o seleziona) un progetto e porta davanti la sua finestra.
    func openProject(_ workspace: Workspace) {
        store.openProject(workspace.id)
        keyWindowController?.activate()
    }

    /// Mostra una pagina nella finestra key; richiederla di nuovo torna ai terminali, se c'è un
    /// progetto da mostrare (stesso gesto per andare e tornare).
    func togglePage(_ page: WindowPage) {
        guard let window = store.keyWindow else { return }
        let showing = WindowPageView.effectivePage(store, windowID: window.id)
        if showing == page, store.selectedWorkspace(in: window.id) != nil {
            window.page = .workspace
        } else {
            if page == .home { applyPendingDecayIfEnabled() } // le righe nascono già decadute
            window.page = page
        }
    }

    /// Decadenza opzionale dei sospesi (`pendingDecayHours` > 0): spegne i pending più vecchi
    /// della soglia. Chiamata nei momenti naturali (boot post-restore, ritorno in foreground,
    /// apertura di Home): niente timer, la granularità è a ore.
    func applyPendingDecayIfEnabled() {
        let hours = settings.pendingDecayHours
        guard hours > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3600)
        let decayed = store.decayPending(olderThan: cutoff)
        if decayed > 0 {
            RelayLog.logger("app").info("pending decay: \(decayed) marker oltre le \(hours)h")
        }
    }

    /// Chiude più progetti fermi (Home, "Quiet for a week") con **una** conferma sola se qualcuno
    /// ha un comando in foreground: un alert per progetto sarebbe una raffica da sbrigare.
    func requestCloseProjects(_ projects: [Workspace]) {
        let busy = projects.filter { project in
            project.tabs.contains { splitVC?.foregroundProcess(for: $0.id) != nil }
        }
        guard let first = projects.first else { return }
        guard !busy.isEmpty else {
            projects.forEach(closeProjectNow)
            return
        }
        let names = busy.map(\.name).joined(separator: ", ")
        confirmCloseProjects(
            count: projects.count,
            info: "Running processes in \(names) will be stopped. Agent sessions can be resumed "
                + "when you open a project again.",
            anchor: first
        ) { [weak self] in
            projects.forEach { self?.closeProjectNow($0) }
        }
    }

    /// L'ultima riga che conta nello schermo di una tab: la domanda se ti aspetta, l'errore se si
    /// è fermata. `nil` se la tab non ha un terminale vivo.
    private func peek(_ tabID: UUID) -> String? {
        let lines = registry.screenLines(for: tabID)
        guard !lines.isEmpty,
              let tab = store.workspaces.lazy.flatMap(\.tabs).first(where: { $0.id == tabID })
        else { return nil }
        let intent: TerminalPeek.Intent = switch tab.agentState {
        case .needsInput: .question
        case .error: .error
        default: .latest
        }
        return TerminalPeek.excerpt(from: lines, intent: intent)
    }

    private func confirmCloseProjects(
        count: Int, info: String, anchor: Workspace, onConfirm: @escaping () -> Void
    ) {
        guard let target = windowControllers[anchor.windowID]?.window ?? window else {
            onConfirm()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Close \(count) projects?"
        alert.informativeText = info
        let closeButton = alert.addButton(withTitle: "Close")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        closeButton.keyEquivalent = "" // Invio non deve chiudere per errore
        cancelButton.keyEquivalent = "\r"
        alert.beginSheetModal(for: target) { response in
            if response == .alertFirstButtonReturn { onConfirm() }
        }
    }
}
