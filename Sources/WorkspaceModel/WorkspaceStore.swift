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
                            resume: tab.resume,
                            // Un completamento mai ripreso sopravvive al riavvio come "in
                            // sospeso": anche `unseen` degrada a pending (al restore il segnale
                            // forte sarebbe stantio; il posto giusto è la dashboard).
                            pendingSince: tab.attention == .none ? nil : tab.lastEventAt
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
                    attention: tab.pendingSince == nil ? .none : .pending,
                    lastEventAt: tab.pendingSince, // ancora l'età del sospeso (dashboard, decay)
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

    /// Porta in vista la prossima (`focusNextAttention`) o precedente (`focusPrevAttention`) tab
    /// che
    /// richiede attenzione, in ordine visivo (`orderedWorkspaces` + ordine tab) e ciclico rispetto
    /// alla selezione corrente. Due livelli: prima l'attenzione fresca (aspetta input o completato
    /// non visto); esauriti quelli, i sospesi (`pending`). Salta sempre la corrente. No-op se
    /// nessuna tab la richiede. Ritorna `true` se la selezione è cambiata.
    @discardableResult
    public func focusNextAttention() -> Bool {
        focusAttention(forward: true)
    }

    @discardableResult
    public func focusPrevAttention() -> Bool {
        focusAttention(forward: false)
    }

    @discardableResult
    private func focusAttention(forward: Bool) -> Bool {
        let flat: [(ws: Workspace, tab: Tab)] = orderedWorkspaces.flatMap { ws in
            ws.tabs.map { (ws, $0) }
        }
        let fresh = flat.indices.filter {
            flat[$0].tab.agentState == .needsInput || flat[$0].tab.attention == .unseen
        }
        let hits = fresh.isEmpty
            ? flat.indices.filter { flat[$0].tab.attention == .pending }
            : fresh
        guard !hits.isEmpty else { return false }
        let current = flat.firstIndex {
            $0.ws.id == selectedWorkspaceID && $0.tab.id == $0.ws.selectedTabID
        } ?? -1
        let targetIndex = forward
            ? (hits.first { $0 > current } ?? hits[0])
            : (hits.last { $0 < current } ?? hits[hits.count - 1])
        let target = flat[targetIndex]
        selectedWorkspaceID = target.ws.id
        target.ws.selectedTabID = target.tab.id
        return true
    }

    /// Seleziona la tab adiacente nel workspace corrente (ciclico). `forward` = la successiva.
    public func selectAdjacentTab(forward: Bool) {
        guard let workspace = selectedWorkspace, !workspace.tabs.isEmpty else { return }
        let tabs = workspace.tabs
        let current = tabs.firstIndex { $0.id == workspace.selectedTabID } ?? 0
        let next = (current + (forward ? 1 : -1) + tabs.count) % tabs.count
        workspace.selectedTabID = tabs[next].id
    }

    /// Seleziona il workspace adiacente in ordine visivo (`orderedWorkspaces`, ciclico).
    public func selectAdjacentWorkspace(forward: Bool) {
        let ordered = orderedWorkspaces
        guard !ordered.isEmpty else { return }
        let current = ordered.firstIndex { $0.id == selectedWorkspaceID } ?? 0
        let next = (current + (forward ? 1 : -1) + ordered.count) % ordered.count
        selectedWorkspaceID = ordered[next].id
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
        appActive: Bool = true,
        resetsAttention: Bool = false
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
                currentAttention: tab.attention,
                resetsAttention: resetsAttention
            )
            tab.agentState = result.state
            tab.attention = result.attention
            tab.lastEventAt = timestamp
            // Notifica (needs_input / completato non visto): classificazione pura, effetto nel
            // composition root. Emessa dopo aver aggiornato la tab (titolo aggiornato dagli hook).
            if let kind = AgentStateReducer.notification(
                current: previousState,
                incoming: state,
                isVisible: isVisible,
                resetsAttention: resetsAttention
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

// MARK: - Attenzione (dismiss e decadenza)

public extension WorkspaceStore {
    /// Dismiss esplicito dell'attenzione di una tab ("era done, niente da fare"): spegne il
    /// marker a qualunque livello (unseen o pending). Ritorna `true` se c'era qualcosa da spegnere.
    @discardableResult
    func dismissAttention(_ tabID: UUID) -> Bool {
        for workspace in workspaces {
            guard let tab = workspace.tabs.first(where: { $0.id == tabID }) else { continue }
            guard tab.attention != .none else { return false }
            tab.attention = .none
            return true
        }
        return false
    }

    /// Decadenza opzionale dei sospesi: spegne i `pending` il cui ultimo evento è più vecchio di
    /// `cutoff`. Chiamata dal composition root quando la preferenza è attiva (boot, ritorno in
    /// foreground, apertura dashboard). Ritorna quanti ne ha spenti.
    @discardableResult
    func decayPending(olderThan cutoff: Date) -> Int {
        var decayed = 0
        for tab in workspaces.flatMap(\.tabs) {
            guard tab.attention == .pending,
                  (tab.lastEventAt ?? .distantPast) < cutoff else { continue }
            tab.attention = .none
            decayed += 1
        }
        return decayed
    }
}
