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

    /// Soglia anti-stantio per gli eventi agente: un evento con `timestamp` anteriore viene
    /// scartato (vedi `applyAgentState`). Il composition root la timbra all'avvio. Serve perché il
    /// `RELAY_TAB_ID` è stabile tra i riavvii: un evento generato prima del restart (`SessionEnd`
    /// in ritardo, hook orfano) arriverebbe con l'id di una tab appena ripristinata e ne
    /// azzererebbe il resume binding. `@ObservationIgnored`: config, non stato UI.
    @ObservationIgnored public var eventFloor: Date?

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

    /// Ordine di visualizzazione della lista principale: esclude gli archiviati (vivono nella loro
    /// sezione), poi pinned (ordine manuale), poi il resto - entrambi **nell'ordine canonico** di
    /// `workspaces`. Nessun float derivato dall'attenzione: la posizione è reale e persistente. Un
    /// completamento/richiesta di input non visti la muovono davvero (`bumpWorkspaceToTop` in
    /// `applyAgentState`), come una lista di chat; poi resta finché non la scavalca un altro bump o
    /// la sposti a mano (drag). L'attenzione è un segnale (badge/ring), non l'ordine.
    public var orderedWorkspaces: [Workspace] {
        let visible = workspaces.filter { !$0.archived }
        return visible.filter(\.pinned) + visible.filter { !$0.pinned }
    }

    /// Workspace archiviati (sezione Archive in fondo alla sidebar), in ordine canonico. Non
    /// galleggiano e non entrano in `orderedWorkspaces`.
    public var archivedWorkspaces: [Workspace] {
        workspaces.filter(\.archived)
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
                    archived: workspace.archived,
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
                            // forte sarebbe stantio; il posto giusto è la dashboard). Persisto il
                            // clock del marker (`attentionSince`), non `lastEventAt`.
                            pendingSince: tab.attention == .none
                                ? nil
                                : (tab.attentionSince ?? tab.lastEventAt)
                        )
                    }
                )
            }
        )
    }

    /// Ricostruisce workspace e tab da uno snapshot (al restore). Le tab nascono senza stato agente
    /// e `unrealized`: la surface parte al primo focus (vedi lifecycle in ARCHITECTURE). La
    /// selezione viene validata contro i workspace effettivamente ricostruiti.
    /// `now` = istante del restore: un marker sopravvissuto degrada a `pending` e il suo clock di
    /// decadenza (`attentionSince`) riparte da qui, così un completamento mai visto non viene
    /// spazzato subito al primo boot (il decay misurerebbe dall'età dell'evento, non da ora).
    public func restore(from snapshot: LayoutSnapshot, now: Date = Date()) {
        workspaces = snapshot.workspaces.map { workspace in
            let tabs = workspace.tabs.map { tab in
                Tab(
                    id: tab.id,
                    title: tab.title,
                    hasCustomTitle: tab.hasCustomTitle,
                    currentDirectory: tab.currentDirectory,
                    attention: tab.pendingSince == nil ? .none : .pending,
                    lastEventAt: tab.pendingSince, // età reale dell'evento (ordinamento dashboard)
                    attentionSince: tab.pendingSince == nil ? nil : now, // clock decay dal boot
                    resume: tab.resume
                )
            }
            // La selezione salvata potrebbe puntare a una tab inesistente (file editato a mano,
            // corruzione parziale che decodifica ancora): validala, altrimenti `Workspace.init`
            // ricade sulla prima tab invece di lasciare il right pane senza tab.
            let selectedTabID = tabs.contains { $0.id == workspace.selectedTabID }
                ? workspace.selectedTabID
                : nil
            return Workspace(
                id: workspace.id,
                name: workspace.name,
                rootPath: workspace.rootPath,
                pinned: workspace.pinned,
                archived: workspace.archived,
                tabs: tabs,
                selectedTabID: selectedTabID
            )
        }
        // La selezione deve puntare a un workspace VISIBILE (non archiviato): setArchived la sposta
        // via dagli archiviati, ma un file editato a mano potrebbe averla lasciata su uno. Ricade
        // sul primo visibile, e solo se tutti sono archiviati (degenere) sul primo assoluto.
        let restoredID = snapshot.selectedWorkspaceID
        selectedWorkspaceID = orderedWorkspaces.contains { $0.id == restoredID }
            ? restoredID
            : orderedWorkspaces.first?.id ?? workspaces.first?.id
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

    /// Archivia o ripristina un workspace (menu contestuale, drag sulla sezione Archive).
    /// Archiviare lo mette via: lo de-pinna (mutuamente esclusivi) e, se era il selezionato, sposta
    /// la selezione al primo visibile. Non archivia l'ultimo workspace visibile (la lista
    /// principale
    /// resterebbe vuota): in quel caso è un no-op. Ripristinare lo rende di nuovo visibile senza
    /// cambiare la selezione.
    public func setArchived(_ id: UUID, _ archived: Bool) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              workspace.archived != archived else { return }
        if archived {
            guard workspaces.contains(where: { !$0.archived && $0.id != id }) else { return }
            workspace.archived = true
            workspace.pinned = false
            if selectedWorkspaceID == id {
                selectedWorkspaceID = orderedWorkspaces.first?.id
            }
        } else {
            workspace.archived = false
        }
    }

    public func toggleArchive(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        setArchived(id, !workspace.archived)
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

    /// Inserisce il workspace `id` immediatamente **prima** di `targetID` nell'ordine canonico
    /// (drag & drop nella sidebar, o bump da attività). `targetID == nil` (o non trovato) lo porta
    /// in fondo. No-op se gli id coincidono o `id` non esiste. La sidebar mostra
    /// `orderedWorkspaces` (canonico, pinned in testa): l'ancora giusta per lo slot visivo la
    /// sceglie `SidebarDrop`.
    public func moveWorkspace(_ id: UUID, before targetID: UUID?) {
        guard id != targetID,
              let from = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let moved = workspaces.remove(at: from)
        if let targetID, let to = workspaces.firstIndex(where: { $0.id == targetID }) {
            workspaces.insert(moved, at: to)
        } else {
            workspaces.append(moved)
        }
    }

    /// Inserisce il workspace `id` immediatamente **dopo** `targetID` nell'ordine canonico. Serve
    /// al drag & drop quando si rilascia in fondo al blocco pinned: lì `before` prenderebbe il
    /// primo del segmento successivo, che in ordine canonico non è contiguo, producendo un no-op.
    /// No-op se gli id coincidono o `id` non esiste.
    public func moveWorkspace(_ id: UUID, after targetID: UUID) {
        guard id != targetID,
              let from = workspaces.firstIndex(where: { $0.id == id }) else { return }
        let moved = workspaces.remove(at: from)
        if let to = workspaces.firstIndex(where: { $0.id == targetID }) {
            workspaces.insert(moved, at: to + 1)
        } else {
            workspaces.append(moved)
        }
    }

    /// Porta il workspace in cima ai non-pinned nell'ordine canonico ("bump" da attività non vista:
    /// un completamento o una richiesta di input arrivati mentre non lo guardavi). È un vero
    /// riordino persistente, non un float derivato: la posizione guadagnata resta finché non la
    /// scavalca un altro bump o non la sposti a mano. No-op se è già in testa ai non-pinned, o se è
    /// pinned/archiviato (i pinned sono già fissi in cima, gli archiviati fuori dalla lista).
    func bumpWorkspaceToTop(_ id: UUID) {
        guard let ws = workspaces.first(where: { $0.id == id }), !ws.pinned, !ws.archived,
              let firstFree = workspaces.first(where: { !$0.pinned && !$0.archived }),
              firstFree.id != id else { return }
        moveWorkspace(id, before: firstFree.id)
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

    /// Inserisce la tab `tabID` immediatamente **prima** di `targetID` nell'ordine del workspace
    /// (drag & drop nella tab bar). `targetID == nil` (o non trovato) la porta in fondo. La tab bar
    /// non ha float: l'ordine è unico, quindi l'indicatore riflette sempre l'esito. La selezione
    /// corrente non cambia (spostare non è selezionare).
    public func moveTab(_ tabID: UUID, before targetID: UUID?, in workspace: Workspace) {
        workspace.moveTab(tabID, before: targetID)
    }

    // Stato agente e marker di attenzione (applyAgentState, dismiss, decadenza): in
    // `WorkspaceStore+AgentState.swift`.
}
