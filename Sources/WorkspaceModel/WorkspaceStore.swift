import AgentProtocol
import Foundation

/// Stato dell'app: la lista di workspace e la selezione corrente. Osservabile, guida la sidebar
/// e l'area di lavoro. Puro: non conosce le surface del terminale (legate per `Tab.id` altrove).
///
/// Le operazioni di chiusura ritornano gli id delle tab rimosse, così il chiamante può fare il
/// teardown delle surface vive corrispondenti.
@Observable
public final class WorkspaceStore {
    /// Scrivibile dal modulo (`internal(set)`), non da fuori: il restore vive in `+Persistence`,
    /// che è un altro file. Dall'esterno resta in sola lettura, e a mutarla sono i comandi.
    public internal(set) var workspaces: [Workspace]
    /// Le finestre aperte. Ce n'è sempre almeno una; partizionano i workspace
    /// (`Workspace.windowID`).
    public internal(set) var windows: [RelayWindow]
    /// La finestra che ha il focus. I comandi globali (menu, scorciatoie) agiscono su di lei.
    public var keyWindowID: UUID

    /// Finestre **occluse**: coperte da altre finestre o minimizzate. Timbrate dal composition root
    /// (`NSWindow.occlusionState`), che è l'unico a saperlo. Guidano `isVisible` insieme ad
    /// `appActive`: una tab montata in una finestra occlusa non la stai guardando, quindi il suo
    /// completamento notifica e bumpa. Non ci lego la finestra **key**: con due monitor la finestra
    /// che fissi spesso non ha il focus, e notificarla sarebbe il bug del caso d'uso principale.
    /// `@ObservationIgnored`: stato di piattaforma, non UI osservata.
    @ObservationIgnored public var occludedWindowIDs: Set<UUID> = []

    /// Ordine di attivazione delle finestre, più recente in testa: quando ne chiudi una, i suoi
    /// workspace rimpatriano nella prima ancora viva. `@ObservationIgnored`: cronologia, non stato
    /// UI.
    @ObservationIgnored var activationOrder: [UUID] = []

    /// Il workspace mostrato nella finestra key. Proiezione: la selezione vera vive sulla finestra,
    /// perché ognuna mostra il suo workspace. Tenuta qui perché menu, scorciatoie e comandi globali
    /// parlano di "il workspace corrente" senza sapere nulla di finestre.
    public var selectedWorkspaceID: UUID? {
        get { keyWindow?.selectedWorkspaceID }
        set { keyWindow?.selectedWorkspaceID = newValue }
    }

    public var keyWindow: RelayWindow? {
        windows.first { $0.id == keyWindowID }
    }

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
        let main = RelayWindow(id: RelayWindow.mainID, selectedWorkspaceID: workspaces.first?.id)
        windows = [main]
        keyWindowID = main.id
        activationOrder = [main.id]
    }

    // MARK: - Query

    public var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    /// Il workspace mostrato in una finestra qualsiasi (non solo la key): è ciò che ogni finestra
    /// renderizza. `selectedWorkspace` è il caso particolare della key.
    public func selectedWorkspace(in windowID: UUID) -> Workspace? {
        guard let selected = windows.first(where: { $0.id == windowID })?.selectedWorkspaceID
        else { return nil }
        return workspaces.first { $0.id == selected }
    }

    /// I workspace di una finestra, nell'ordine canonico.
    public func workspaces(in windowID: UUID) -> [Workspace] {
        workspaces.filter { $0.windowID == windowID }
    }

    /// Ordine di visualizzazione della sidebar **di una finestra**: solo i suoi workspace, non
    /// archiviati, pinned in testa. Vedi `orderedWorkspaces` per la finestra key.
    public func orderedWorkspaces(in windowID: UUID) -> [Workspace] {
        let visible = workspaces.filter { $0.windowID == windowID && !$0.archived }
        return visible.filter(\.pinned) + visible.filter { !$0.pinned }
    }

    /// Gli archiviati di una finestra (la sua sezione Archive).
    public func archivedWorkspaces(in windowID: UUID) -> [Workspace] {
        workspaces.filter { $0.windowID == windowID && $0.archived }
    }

    /// Ordine di visualizzazione della lista principale: esclude gli archiviati (vivono nella loro
    /// sezione), poi pinned (ordine manuale), poi il resto - entrambi **nell'ordine canonico** di
    /// `workspaces`. Nessun float derivato dall'attenzione: la posizione è reale e persistente. Un
    /// completamento/richiesta di input non visti la muovono davvero (`bumpWorkspaceToTop` in
    /// `applyAgentState`), come una lista di chat; poi resta finché non la scavalca un altro bump o
    /// la sposti a mano (drag). L'attenzione è un segnale (badge/ring), non l'ordine.
    public var orderedWorkspaces: [Workspace] {
        orderedWorkspaces(in: keyWindowID)
    }

    /// Workspace archiviati (sezione Archive in fondo alla sidebar), in ordine canonico. Non
    /// galleggiano e non entrano in `orderedWorkspaces`.
    public var archivedWorkspaces: [Workspace] {
        archivedWorkspaces(in: keyWindowID)
    }

    // MARK: - Workspace

    /// Crea un workspace. `nameOrigin` di default `.default` (eleggibile alla nomina automatica: il
    /// nome è un placeholder "Workspace N" o il basename della cartella aperta, che la nomina AI
    /// può
    /// migliorare). Passa `.user` per i nomi intenzionali che non vanno rigenerati (es. "Relay
    /// Update").
    /// Nasce nella finestra indicata (`nil` = la key) e ne diventa la selezione, salvo
    /// `select: false`: il workspace transitorio di `newWindow` migra subito, e selezionarlo
    /// farebbe perdere alla finestra d'origine la riga su cui stavi lavorando.
    @discardableResult
    public func createWorkspace(
        name: String,
        nameOrigin: NameOrigin = .default,
        rootPath: String? = nil,
        in windowID: UUID? = nil,
        select: Bool = true
    ) -> Workspace {
        let target = windowID.flatMap { id in windows.first { $0.id == id }?.id } ?? keyWindowID
        let workspace = Workspace(
            windowID: target, name: name, nameOrigin: nameOrigin, rootPath: rootPath
        )
        workspaces.append(workspace)
        if select {
            windows.first { $0.id == target }?.selectedWorkspaceID = workspace.id
        }
        addTab(to: workspace) // ogni workspace nasce con una tab
        return workspace
    }

    /// Seleziona il workspace **nella sua finestra**, che diventa la key: selezionarne uno che vive
    /// altrove significa passare a quella finestra, non trascinarlo qui.
    public func selectWorkspace(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        activateWindow(workspace.windowID)
        keyWindow?.selectedWorkspaceID = id
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
        let window = workspace.windowID
        if archived {
            // L'ultimo visibile **della sua finestra**: archiviarlo lascerebbe quella sidebar
            // vuota.
            let hasVisibleSibling = workspaces.contains {
                !$0.archived && $0.id != id && $0.windowID == window
            }
            guard hasVisibleSibling else { return }
            workspace.archived = true
            workspace.pinned = false
            let owner = windows.first { $0.id == window }
            if owner?.selectedWorkspaceID == id {
                owner?.selectedWorkspaceID = orderedWorkspaces(in: window).first?.id
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
        let window = workspaces[index].windowID
        let removedTabIDs = workspaces[index].tabs.map(\.id)
        workspaces.remove(at: index)
        // La selezione della finestra che lo mostrava cade su un vicino **della stessa finestra**:
        // una finestra non può mostrare un workspace che non le appartiene.
        if let owner = windows.first(where: { $0.id == window }), owner.selectedWorkspaceID == id {
            let siblings = workspaces(in: window)
            owner.selectedWorkspaceID = (orderedWorkspaces(in: window).first ?? siblings.first)?.id
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
              // In cima **alla sua sidebar**: il bump riordina dentro la finestra che lo mostra,
              // non lo strappa in testa alla lista globale (che nessuno vede intera).
              let firstFree = workspaces.first(where: {
                  !$0.pinned && !$0.archived && $0.windowID == ws.windowID
              }),
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

    /// Seleziona una tab: la **rivela** (selezionata nel suo pane + focus a quel pane, vedi
    /// `Workspace.reveal`). Tutta la navigazione passa di qui, quindi la eredita gratis.
    public func selectTab(_ tabID: UUID, in workspace: Workspace) {
        workspace.reveal(tabID)
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
        // Nella finestra del workspace d'origine, non nella key: l'azione parte dalla sua strip,
        // e un nuovo workspace che finisse in un'altra finestra violerebbe la partizione (sidebar
        // che non lo lista, stessa surface montata in due aree).
        let newWorkspace = Workspace(
            windowID: workspace.windowID,
            name: name,
            nameOrigin: nameOrigin,
            rootPath: tab.currentDirectory,
            tabs: [tab],
            selectedTabID: tab.id
        )
        workspaces.append(newWorkspace)
        workspace.removeTab(tabID)
        windows.first { $0.id == workspace.windowID }?.selectedWorkspaceID = newWorkspace.id
        return newWorkspace
    }

    // Stato agente e marker di attenzione (applyAgentState, dismiss, decadenza): in
    // `WorkspaceStore+AgentState.swift`.
}
