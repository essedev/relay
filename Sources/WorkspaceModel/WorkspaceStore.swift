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

    /// Effetto per il "flash" di completamento sulla tab in vista: lo store lo chiama con l'id
    /// della tab quando il lavoro finisce mentre la guardi. Il completamento nasce forte (`unseen`:
    /// ring + flash + badge pieno) e il composition root schedula un mark-read differito che dopo
    /// qualche secondo lo declassa a `pending` (via `markSeen`). Fuori di qui perché richiede un
    /// timer (AppKit/dispatch), che lo store puro non ha. `@ObservationIgnored`: hook imperativo.
    @ObservationIgnored public var onVisibleCompletion: ((UUID) -> Void)?

    /// Soglia anti-stantio per gli eventi agente: un evento con `timestamp` anteriore viene
    /// scartato (vedi `applyAgentState`). Il composition root la timbra all'avvio. Serve perché il
    /// `RELAY_TAB_ID` è stabile tra i riavvii: un evento generato prima del restart (`SessionEnd`
    /// in ritardo, hook orfano) arriverebbe con l'id di una tab appena ripristinata e ne
    /// azzererebbe il resume binding. `@ObservationIgnored`: config, non stato UI.
    @ObservationIgnored public var eventFloor: Date?

    /// Fence di run per gli eventi agente: se impostato, `applyAgentState` scarta gli eventi il
    /// cui `runId` non coincide (compresi quelli senza runId). Il composition root lo timbra
    /// all'avvio (`RELAY_RUN_ID`, iniettato nell'env delle surface). Complementare a `eventFloor`:
    /// il floor ferma gli hook *eseguiti* prima del boot, il fence quelli eseguiti dopo ma nati da
    /// sessioni di run precedenti (claude orfani sopravvissuti al riavvio), che il timestamp
    /// fresco farebbe passare. `nil` = fence spento (test, chiamate dirette).
    @ObservationIgnored public var runID: String?

    public init(workspaces: [Workspace] = []) {
        self.workspaces = workspaces
        selectedWorkspaceID = workspaces.first?.id
    }

    // MARK: - Query

    public var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
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
                    nameOrigin: workspace.nameOrigin,
                    rootPath: workspace.rootPath,
                    pinned: workspace.pinned,
                    archived: workspace.archived,
                    selectedTabID: workspace.selectedTabID,
                    splitLayout: workspace.splitLayout,
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
            // Stesso trattamento per il layout: un pane che punta a una tab sparita non è
            // renderizzabile, quindi le foglie orfane (e le duplicate) cadono e il ramo collassa.
            let layout = workspace.splitLayout?.sanitized(keeping: Set(tabs.map(\.id)))
            let restored = Workspace(
                id: workspace.id,
                name: workspace.name,
                nameOrigin: workspace.nameOrigin,
                rootPath: workspace.rootPath,
                pinned: workspace.pinned,
                archived: workspace.archived,
                tabs: tabs,
                selectedTabID: selectedTabID,
                splitLayout: layout
            )
            // Riporta il layout alla forma canonica (una foglia sola = pane singolo) e riaggancia
            // la focused a un pane montato, se la selezione salvata è caduta fuori dall'albero.
            restored.normalizeLayout()
            return restored
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

    /// Crea un workspace. `nameOrigin` di default `.default` (eleggibile alla nomina automatica: il
    /// nome è un placeholder "Workspace N" o il basename della cartella aperta, che la nomina AI
    /// può
    /// migliorare). Passa `.user` per i nomi intenzionali che non vanno rigenerati (es. "Relay
    /// Update").
    @discardableResult
    public func createWorkspace(
        name: String,
        nameOrigin: NameOrigin = .default,
        rootPath: String? = nil
    ) -> Workspace {
        let workspace = Workspace(name: name, nameOrigin: nameOrigin, rootPath: rootPath)
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

    /// Rinomina un workspace (azione utente esplicita dal menu contestuale). Nome vuoto (solo
    /// spazi)
    /// ignorato: si tiene quello vecchio. Marca l'origine `.user`: un nome scelto a mano è
    /// intoccabile, la nomina automatica non lo sovrascrive più.
    public func renameWorkspace(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let workspace = workspaces.first(where: { $0.id == id }) else { return }
        workspace.name = trimmed
        workspace.nameOrigin = .user
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
        workspaces.move(id, before: targetID)
    }

    /// Inserisce il workspace `id` immediatamente **dopo** `targetID` nell'ordine canonico. Serve
    /// al drag & drop quando si rilascia in fondo al blocco pinned: lì `before` prenderebbe il
    /// primo del segmento successivo, che in ordine canonico non è contiguo, producendo un no-op.
    /// No-op se gli id coincidono o `id` non esiste.
    public func moveWorkspace(_ id: UUID, after targetID: UUID) {
        workspaces.move(id, after: targetID)
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

    /// La nuova tab eredita la working directory: `currentDirectory` se il chiamante l'ha risolta
    /// dalla shell viva (precedenza in `Core.CurrentDirectory`), altrimenti l'ultima cwd nota della
    /// tab selezionata. Così `Cmd+T` apre dove stai lavorando, non alla radice del workspace.
    /// `nil` = nessuna cwd nota, e la tab non ne inventa una: la surface parte dalla root del
    /// workspace (fallback a runtime, nell'area).
    @discardableResult
    public func addTab(
        to workspace: Workspace,
        title: String = Tab.defaultTitle, currentDirectory: String? = nil
    ) -> Tab {
        let inherited = currentDirectory ?? workspace.selectedTab?.currentDirectory
        return workspace.appendTab(Tab(title: title, currentDirectory: inherited), select: true)
    }

    /// Seleziona una tab: **monta o metti a fuoco** (vedi `Workspace.mount`). Con uno split aperto,
    /// una tab già in un pane riceve solo il focus; una non montata prende il posto di quella nel
    /// pane focused. Tutta la navigazione passa di qui, quindi la eredita gratis.
    public func selectTab(_ tabID: UUID, in workspace: Workspace) {
        guard workspace.tabs.contains(where: { $0.id == tabID }) else { return }
        workspace.mount(tabID)
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

    /// Sposta una tab in un **nuovo** workspace preservando la sessione viva: sposta lo stesso
    /// oggetto `Tab` (stesso `Tab.id`), quindi la surface legata per id resta intatta - nessun
    /// teardown del pty, il lavoro dentro la tab non si tocca. Il nuovo workspace eredita la cwd
    /// della tab come `rootPath` e nasce `.default` (eleggibile alla nomina automatica: il nome
    /// passato è un placeholder). Diventa il selezionato, con la tab spostata attiva.
    ///
    /// **No-op se la tab è l'unica del suo workspace** (sarebbe solo un rename del workspace, e
    /// svuoterebbe l'origine) o se `tabID` non esiste lì. Ritorna il nuovo workspace, o `nil` se
    /// no-op. L'append + il remove avvengono nella stessa mutazione sincrona, così la tab è sempre
    /// presente in `store.workspaces` a ogni istante osservabile: il reconcile delle surface
    /// (`retain` su tutti gli id) non la sfratta mai (vedi TerminalHostUI).
    @discardableResult
    public func moveTabToNewWorkspace(
        _ tabID: UUID,
        from workspace: Workspace,
        name: String,
        nameOrigin: NameOrigin = .default
    ) -> Workspace? {
        guard workspace.tabs.count > 1,
              let tab = workspace.tabs.first(where: { $0.id == tabID }) else { return nil }
        let newWorkspace = Workspace(
            name: name,
            nameOrigin: nameOrigin,
            rootPath: tab.currentDirectory,
            tabs: [tab],
            selectedTabID: tab.id
        )
        workspaces.append(newWorkspace)
        workspace.removeTab(tabID)
        selectedWorkspaceID = newWorkspace.id
        return newWorkspace
    }

    // Stato agente e marker di attenzione (applyAgentState, dismiss, decadenza): in
    // `WorkspaceStore+AgentState.swift`.
}
