import AgentProtocol
import Foundation

/// Stato dell'app: la lista di workspace e la selezione corrente. Osservabile, guida la sidebar
/// e l'area di lavoro. Puro: non conosce le surface del terminale (legate per `Tab.id` altrove).
///
/// Le operazioni di chiusura ritornano gli id delle tab rimosse, così il chiamante può fare il
/// teardown delle surface vive corrispondenti.
@Observable
public final class WorkspaceStore {
    public private(set) var workspaces: [Workspace]
    public var selectedWorkspaceID: UUID?

    /// Effetto per le notifiche macOS: il composition root lo aggancia a `UNUserNotificationCenter`
    /// e lo store lo chiama quando una transizione la merita. Dati puri, nessun AppKit qui.
    /// `@ObservationIgnored`: è un hook imperativo, non stato osservato.
    @ObservationIgnored public var onNotifiableTransition: ((AgentNotification) -> Void)?

    public init(workspaces: [Workspace] = []) {
        self.workspaces = workspaces
        selectedWorkspaceID = workspaces.first?.id
    }

    // MARK: - Query

    public var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    public var pinnedWorkspaces: [Workspace] {
        workspaces.filter(\.pinned)
    }

    public var otherWorkspaces: [Workspace] {
        workspaces.filter { !$0.pinned }
    }

    /// Ordine di visualizzazione: pinned (ordine manuale), poi i workspace con attenzione
    /// (`needs_input`/completato), poi il resto. Partizione stabile: dentro ogni gruppo resta
    /// l'ordine canonico di `workspaces`; il float è solo derivato dallo stato live (drag e
    /// persistence agiscono sull'ordine canonico).
    public var orderedWorkspaces: [Workspace] {
        let pinned = workspaces.filter(\.pinned)
        let rest = workspaces.filter { !$0.pinned }
        return pinned + rest.filter(\.needsAttention) + rest.filter { !$0.needsAttention }
    }

    // MARK: - Persistence

    /// Fotografa il layout corrente (per il salvataggio su disco). Solo dati persistenti: niente
    /// stato agente né surface.
    public func snapshot() -> LayoutSnapshot {
        LayoutSnapshot(
            selectedWorkspaceID: selectedWorkspaceID,
            workspaces: workspaces.map { workspace in
                WorkspaceSnapshot(
                    id: workspace.id,
                    name: workspace.name,
                    rootPath: workspace.rootPath,
                    pinned: workspace.pinned,
                    selectedTabID: workspace.selectedTabID,
                    tabs: workspace.tabs.map { tab in
                        TabSnapshot(
                            id: tab.id,
                            title: tab.title,
                            hasCustomTitle: tab.hasCustomTitle,
                            currentDirectory: tab.currentDirectory,
                            resume: tab.resume
                        )
                    }
                )
            }
        )
    }

    /// Ricostruisce workspace e tab da uno snapshot (al restore). Le tab nascono senza stato agente
    /// e `unrealized`: la surface parte al primo focus (vedi lifecycle in ARCHITECTURE). La
    /// selezione viene validata contro i workspace effettivamente ricostruiti.
    public func restore(from snapshot: LayoutSnapshot) {
        workspaces = snapshot.workspaces.map { workspace in
            let tabs = workspace.tabs.map { tab in
                Tab(
                    id: tab.id,
                    title: tab.title,
                    hasCustomTitle: tab.hasCustomTitle,
                    currentDirectory: tab.currentDirectory,
                    resume: tab.resume
                )
            }
            return Workspace(
                id: workspace.id,
                name: workspace.name,
                rootPath: workspace.rootPath,
                pinned: workspace.pinned,
                tabs: tabs,
                selectedTabID: workspace.selectedTabID
            )
        }
        let restoredID = snapshot.selectedWorkspaceID
        selectedWorkspaceID = workspaces.contains { $0.id == restoredID }
            ? restoredID
            : workspaces.first?.id
    }

    // MARK: - Workspace

    @discardableResult
    public func createWorkspace(name: String, rootPath: String? = nil) -> Workspace {
        let workspace = Workspace(name: name, rootPath: rootPath)
        workspaces.append(workspace)
        selectedWorkspaceID = workspace.id
        addTab(to: workspace) // ogni workspace nasce con una tab
        return workspace
    }

    public func selectWorkspace(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        selectedWorkspaceID = id
    }

    public func togglePin(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        workspace.pinned.toggle()
    }

    /// Rinomina un workspace. Nome vuoto (solo spazi) ignorato: si tiene quello vecchio.
    public func renameWorkspace(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let workspace = workspaces.first(where: { $0.id == id }) else { return }
        workspace.name = trimmed
    }

    /// Rimuove un workspace. Ritorna gli id delle tab rimosse (per il teardown delle surface).
    @discardableResult
    public func closeWorkspace(_ id: UUID) -> [UUID] {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return [] }
        let removedTabIDs = workspaces[index].tabs.map(\.id)
        workspaces.remove(at: index)
        if selectedWorkspaceID == id {
            let neighbor = workspaces[safe: index] ?? workspaces[safe: index - 1] ?? workspaces.last
            selectedWorkspaceID = neighbor?.id
        }
        return removedTabIDs
    }

    public func moveWorkspaces(fromOffsets: IndexSet, toOffset: Int) {
        workspaces.moveElements(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    /// Sposta il workspace `id` nella posizione corrente di `targetID` (drag & drop nella sidebar):
    /// il target e i successivi scorrono. No-op se un id non esiste o coincidono.
    public func moveWorkspace(_ id: UUID, onto targetID: UUID) {
        guard id != targetID,
              let from = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let moved = workspaces.remove(at: from)
        guard let to = workspaces.firstIndex(where: { $0.id == targetID }) else {
            workspaces.append(moved)
            return
        }
        workspaces.insert(moved, at: to)
    }

    // MARK: - Tab

    /// La nuova tab eredita la working directory corrente della tab selezionata (se nota via
    /// OSC 7): `Cmd+T` apre dove stai lavorando, non alla radice del workspace.
    @discardableResult
    public func addTab(to workspace: Workspace, title: String = Tab.defaultTitle) -> Tab {
        let inherited = workspace.selectedTab?.currentDirectory
        return workspace.appendTab(Tab(title: title, currentDirectory: inherited), select: true)
    }

    public func selectTab(_ tabID: UUID, in workspace: Workspace) {
        guard workspace.tabs.contains(where: { $0.id == tabID }) else { return }
        workspace.selectedTabID = tabID
    }

    /// Porta in vista la prossima tab che richiede attenzione (aspetta input o ha completato del
    /// lavoro non visto), in ordine visivo (`orderedWorkspaces` + ordine tab) e ciclico rispetto
    /// alla selezione corrente. Seleziona sia il workspace sia la tab. Salta sempre la corrente
    /// (premendo ripetutamente si scorrono tutte), riparte dall'inizio dopo l'ultima. No-op se
    /// nessuna tab richiede attenzione. Ritorna `true` se la selezione è cambiata.
    @discardableResult
    public func focusNextAttention() -> Bool {
        let flat: [(ws: Workspace, tab: Tab)] = orderedWorkspaces.flatMap { ws in
            ws.tabs.map { (ws, $0) }
        }
        let attentionIndices = flat.indices.filter {
            flat[$0].tab.agentState == .needsInput || flat[$0].tab.attention
        }
        guard !attentionIndices.isEmpty else { return false }
        let currentIndex = flat.firstIndex {
            $0.ws.id == selectedWorkspaceID && $0.tab.id == $0.ws.selectedTabID
        } ?? -1
        let target = flat[attentionIndices.first { $0 > currentIndex } ?? attentionIndices[0]]
        selectedWorkspaceID = target.ws.id
        target.ws.selectedTabID = target.tab.id
        return true
    }

    /// Chiude una tab. Ritorna l'id rimosso (per il teardown della surface).
    /// Chiudere l'ultima tab di un workspace chiude anche il workspace (cascade): un progetto
    /// senza terminali non ha senso di esistere.
    @discardableResult
    public func closeTab(_ tabID: UUID, in workspace: Workspace) -> UUID? {
        let removed = workspace.removeTab(tabID)
        if removed != nil, workspace.tabs.isEmpty {
            closeWorkspace(workspace.id)
        }
        return removed
    }

    public func renameTab(_ tabID: UUID, in workspace: Workspace, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let tab = workspace.tabs.first(where: { $0.id == tabID }) else { return }
        tab.title = trimmed
        tab.hasCustomTitle = true
    }

    // MARK: - Stato agente

    /// Applica un evento agente alla tab identificata da `paneId` (= `RELAY_TAB_ID` = `Tab.id`).
    /// `isVisible` = tab in vista **e** app in primo piano (`appActive`): se Relay è in background
    /// non la stai guardando davvero, anche se è la tab selezionata, quindi il completamento resta
    /// segnalato e la notifica parte. `appActive` lo passa il composition root (`NSApp.isActive`);
    /// default `true` per i test/chiamate diretti.
    /// Ritorna `false` se `paneId` non è un UUID valido o non corrisponde a nessuna tab (no-op).
    @discardableResult
    public func applyAgentState(
        paneId: String,
        agent: String = "",
        sessionId: String = "",
        state: AgentState,
        at timestamp: Date,
        appActive: Bool = true
    ) -> Bool {
        guard let tabID = UUID(uuidString: paneId) else { return false }
        for workspace in workspaces {
            guard let tab = workspace.tabs.first(where: { $0.id == tabID }) else { continue }
            let isSelected = selectedWorkspaceID == workspace.id
                && workspace.selectedTabID == tab.id
            let isVisible = isSelected && appActive
            let previousState = tab.agentState
            let result = AgentStateReducer.reduce(
                current: previousState,
                incoming: state,
                isVisible: isVisible,
                currentAttention: tab.attention
            )
            tab.agentState = result.state
            tab.attention = result.attention
            tab.lastEventAt = timestamp
            // Notifica (needs_input / completato non visto): classificazione pura, effetto nel
            // composition root. Emessa dopo aver aggiornato la tab (titolo aggiornato dagli hook).
            if let kind = AgentStateReducer.notification(
                current: previousState,
                incoming: state,
                isVisible: isVisible
            ) {
                onNotifiableTransition?(AgentNotification(
                    kind: kind,
                    tabTitle: tab.title,
                    workspaceName: workspace.name,
                    isVisible: isVisible
                ))
            }
            // Resume binding: aggiornato finché la sessione è viva, azzerato alla chiusura
            // (`unknown` = SessionEnd). `sessionId` vuoto (test/simulazioni base) non crea binding.
            if state == .unknown {
                tab.resume = nil
            } else if !sessionId.isEmpty {
                tab.resume = ResumeBinding(agent: agent, sessionId: sessionId, label: tab.title)
            }
            return true
        }
        return false
    }
}
