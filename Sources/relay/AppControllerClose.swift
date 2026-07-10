import AgentProtocol
import AppKit
import WorkspaceModel

/// Chiusura di tab e workspace con conferma quando c'è lavoro in corso (Cmd+W e le x dei pannelli).
/// Estratto dal corpo di `AppController` per tenerlo sul solo wiring: la policy (quando chiedere) e
/// la presentazione (l'alert) stanno qui.
extension AppController {
    /// Chiude una tab, chiedendo conferma se nel suo pty gira un comando in foreground (build,
    /// ssh, Claude...). Shell al prompt o tab mai realizzata -> chiude subito. Lo stato agente
    /// arricchisce solo il messaggio. Chiudere l'ultima tab chiude il workspace (cascade nello
    /// store): quel caso è già coperto dalla conferma della tab, niente doppio prompt.
    func requestCloseTab(_ tab: WorkspaceModel.Tab, in workspace: Workspace) {
        guard let process = splitVC?.foregroundProcess(for: tab.id) else {
            performCloseTab(tab, in: workspace)
            return
        }
        confirmClose(
            title: "Close tab \u{201C}\(tab.title)\u{201D}?",
            info: closeInfo(process: process, agentState: tab.agentState)
        ) { [weak self] in
            self?.performCloseTab(tab, in: workspace)
        }
    }

    /// Chiude un pane **con le sue tab** (le sessioni muoiono, come chiudere quelle tab una per
    /// una), chiedendo conferma se qualcuna ha un comando in foreground. No-op sull'ultimo pane
    /// (lo garantisce lo store). Il `workspace` arriva dal chiamante (strip o shortcut), non dalla
    /// proiezione della key window.
    func requestClosePane(_ paneID: UUID, in workspace: Workspace) {
        let tabs = workspace.layout.pane(paneID)?.tabIDs ?? []
        let busy = tabs.filter { splitVC?.foregroundProcess(for: $0) != nil }
        guard !busy.isEmpty else {
            store.closePane(paneID, in: workspace)
            return
        }
        let info = busy.count == 1
            ? "1 tab in this pane has a running process that will be terminated."
            : "\(busy.count) tabs in this pane have running processes that will be terminated."
        confirmClose(title: "Close this pane?", info: info) { [weak self] in
            self?.store.closePane(paneID, in: workspace)
        }
    }

    /// Chiude un workspace, chiedendo conferma se una qualsiasi delle sue tab ha un comando in
    /// foreground.
    func requestCloseWorkspace(_ workspace: Workspace) {
        let busy = workspace.tabs.filter { splitVC?.foregroundProcess(for: $0.id) != nil }
        guard !busy.isEmpty else {
            performCloseWorkspace(workspace)
            return
        }
        let info = busy.count == 1
            ? "1 tab has a running process that will be terminated."
            : "\(busy.count) tabs have running processes that will be terminated."
        confirmClose(
            title: "Close workspace \u{201C}\(workspace.name)\u{201D}?",
            info: info
        ) { [weak self] in
            self?.performCloseWorkspace(workspace)
        }
    }

    /// Esegue la chiusura effettiva, poi ripristina l'invariante "almeno un workspace": chiudere
    /// l'ultima tab (cascade sul workspace) o l'ultimo workspace ne apre subito uno default, così
    /// la finestra non resta mai vuota.
    private func performCloseTab(_ tab: WorkspaceModel.Tab, in workspace: Workspace) {
        store.closeTab(tab.id, in: workspace)
        ensureAtLeastOneWorkspace()
    }

    private func performCloseWorkspace(_ workspace: Workspace) {
        store.closeWorkspace(workspace.id)
        ensureAtLeastOneWorkspace()
    }

    private func ensureAtLeastOneWorkspace() {
        if store.workspaces.isEmpty { createUntitledWorkspace() }
    }

    /// Messaggio della conferma: privilegia Claude per ogni stato di sessione viva - anche ferma
    /// al prompt (`idle`) il processo è in foreground e la chiusura la interrompe; il proc_name
    /// grezzo sarebbe la versione ("2.1.200"), incomprensibile. `.unknown` = nessuna sessione nota
    /// in questa run (mai partita, chiusa da SessionEnd, o tab appena ripristinata: `resume` non
    /// basta a dire "Claude", dopo un restore nel pty può girare tutt'altro): lì il nome del
    /// processo è l'informazione più onesta. Niente promessa di ripresa: chiudere la tab butta
    /// anche il suo `ResumeBinding`.
    private func closeInfo(process: String, agentState: AgentState) -> String {
        switch agentState {
        case .running:
            "Claude is working in this tab. Closing it will interrupt the session."
        case .needsInput:
            "Claude is waiting for your reply. Closing it will interrupt the session."
        case .idle, .error:
            "This tab has an open Claude session. Closing it will interrupt it."
        case .unknown:
            "\u{201C}\(process)\u{201D} is running. Closing the tab will terminate it."
        }
    }

    /// Alert di conferma come sheet sulla finestra. Default sicuro: Invio annulla (non chiude).
    private func confirmClose(title: String, info: String, onConfirm: @escaping () -> Void) {
        guard let window else { onConfirm(); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = info
        let closeButton = alert.addButton(withTitle: "Close")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        closeButton.keyEquivalent = "" // Invio non deve chiudere per errore
        cancelButton.keyEquivalent = "\r"
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { onConfirm() }
        }
    }
}
