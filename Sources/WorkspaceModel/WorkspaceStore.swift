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
    /// I gruppi della sidebar. Solo identità e aspetto (nome, colore, collasso, pin): i **membri**
    /// stanno sul workspace (`Workspace.groupID`), quindi non c'è una seconda lista d'ordine da
    /// tenere in sync. Un gruppo senza membri non esiste: le operazioni lo cancellano (vedi
    /// `WorkspaceStore+Groups`).
    public internal(set) var groups: [WorkspaceGroup]
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

    /// Simmetrico di `onNotifiableTransition`: la tab non aspetta più niente (l'hai vista, l'hai
    /// dismessa, il sospeso è decaduto, l'hai chiusa), quindi la sua notifica macOS non ha più
    /// niente da dire e il composition root la ritira dal centro notifiche. Senza, un banner
    /// sopravvive alla cosa che lo ha generato e il centro notifiche accumula una voce per ogni
    /// tab che ha mai chiamato. `@ObservationIgnored`: hook imperativo.
    @ObservationIgnored public var onAttentionCleared: ((UUID) -> Void)?

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

    public init(workspaces: [Workspace] = [], groups: [WorkspaceGroup] = []) {
        self.workspaces = workspaces
        self.groups = groups
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
    /// archiviati, pinned in testa. I membri di un gruppo stanno insieme, alla posizione del
    /// gruppo (vedi `sidebarItems`); ci sono anche quelli dei gruppi **collassati**, che a schermo
    /// non si vedono ma restano nell'ordine logico (`Cmd+J`, eredi di selezione). Per le
    /// scorciatoie numeriche serve invece `navigableWorkspaces`. Vedi `orderedWorkspaces` per la
    /// finestra key.
    public func orderedWorkspaces(in windowID: UUID) -> [Workspace] {
        sidebarItems(in: windowID).flatMap(\.workspaces)
    }

    /// I progetti chiusi di una finestra, in ordine canonico.
    public func closedWorkspaces(in windowID: UUID) -> [Workspace] {
        workspaces.filter { $0.windowID == windowID && $0.closed }
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

    /// Progetti chiusi della finestra key, in ordine canonico. Non galleggiano e non entrano in
    /// `orderedWorkspaces`.
    public var closedWorkspaces: [Workspace] {
        closedWorkspaces(in: keyWindowID)
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
    ///
    /// Nasce **accanto al workspace su cui stai lavorando** (`insertionAnchor`), non in fondo alla
    /// lista: creare è un gesto contestuale, e il fondo è per giunta il posto che il primo bump
    /// altrui scavalca.
    @discardableResult
    public func createWorkspace(
        name: String,
        nameOrigin: NameOrigin = .default,
        rootPath: String? = nil,
        in windowID: UUID? = nil,
        select: Bool = true
    ) -> Workspace {
        let target = windowID.flatMap { id in windows.first { $0.id == id }?.id } ?? keyWindowID
        let anchor = insertionAnchor(in: target)
        let workspace = Workspace(
            windowID: target, name: name, nameOrigin: nameOrigin, rootPath: rootPath,
            groupID: anchor?.groupID
        )
        workspaces.append(workspace)
        if let anchor { workspaces.move(workspace.id, after: anchor.id) }
        if select {
            windows.first { $0.id == target }?.selectedWorkspaceID = workspace.id
            // Nato in una card **chiusa**: la si apre, come fa `reveal`. Altrimenti il selezionato
            // sarebbe una riga che in sidebar non si vede.
            if let groupID = workspace.groupID { group(groupID)?.collapsed = false }
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
        // Scegliere un progetto è andarci: la pagina (Home, Projects) lascia il posto ai terminali.
        keyWindow?.page = .workspace
    }

    /// Pin di una riga libera. **No-op dentro un gruppo**: lì a salire in testa è la card intera
    /// (`setGroupPinned`), non il singolo membro - due pin sovrapposti darebbero una riga pinned
    /// che la card tiene comunque in mezzo agli altri.
    public func togglePin(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              workspace.groupID == nil else { return }
        workspace.pinned.toggle()
    }

    /// Chiude o riapre un progetto. Chiudere è il gesto **normale** per mettere via un progetto,
    /// quindi non deve far perdere niente: il workspace resta con nome, cartella, gruppo, layout e
    /// tab, e le sessioni agente vengono disattivate tenendo il loro `ResumeBinding` (stesso
    /// marker di `deactivate`, così l'hook `SessionEnd` dell'agente che muore non lo azzera).
    /// Riaprire lo rimette in sidebar: le surface rinascono al primo focus e la barra di resume
    /// ripropone le sessioni, come dopo un riavvio.
    ///
    /// Chiudendo: de-pinna, spegne i marker di attenzione (l'hai messo via tu, non ti sta
    /// aspettando) e, se era il selezionato della sua finestra, la selezione passa al primo
    /// aperto; se non ne restano, la finestra mostra Home. Il gruppo **resta**: la card mostra solo
    /// i membri aperti e torna quando ne riapri uno.
    ///
    /// Ritorna gli id delle tab le cui surface vanno buttate (tutte, chiudendo; nessuna,
    /// riaprendo). Marca prima, la surface la butta il chiamante **dopo**: l'ordine è quello della
    /// disattivazione (vedi `docs/features/session-deactivation.md`).
    @discardableResult
    public func setClosed(_ id: UUID, _ closed: Bool) -> [UUID] {
        guard let workspace = workspaces.first(where: { $0.id == id }),
              workspace.closed != closed else { return [] }
        guard closed else {
            workspace.closed = false
            return []
        }
        let window = workspace.windowID
        let tabIDs = workspace.tabs.map(\.id)
        deactivate(Set(tabIDs))
        for tabID in tabIDs {
            dismissAttention(tabID)
        }
        workspace.closed = true
        workspace.pinned = false
        if let owner = windows.first(where: { $0.id == window }), owner.selectedWorkspaceID == id {
            let heir = orderedWorkspaces(in: window).first
            owner.selectedWorkspaceID = heir?.id
            if heir == nil { owner.page = .home }
        }
        return tabIDs
    }

    @discardableResult
    public func toggleClosed(_ id: UUID) -> [UUID] {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return [] }
        return setClosed(id, !workspace.closed)
    }

    /// Riapre un progetto chiuso e lo porta in vista nella sua finestra, con la card del suo
    /// gruppo aperta. Su un progetto già aperto è solo la selezione.
    public func openProject(_ id: UUID) {
        guard let workspace = workspaces.first(where: { $0.id == id }) else { return }
        setClosed(id, false)
        if let groupID = workspace.groupID { group(groupID)?.collapsed = false }
        selectWorkspace(id)
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
        pruneEmptyGroups() // era l'ultimo membro della sua card: la card se ne va con lui
        // La selezione della finestra che lo mostrava cade su un vicino **della stessa finestra**:
        // una finestra non può mostrare un workspace che non le appartiene.
        if let owner = windows.first(where: { $0.id == window }), owner.selectedWorkspaceID == id {
            // Solo un aperto: un chiuso selezionato sarebbe un right pane senza terminali. Se non
            // ne restano, la finestra mostra Home.
            let heir = orderedWorkspaces(in: window).first
            owner.selectedWorkspaceID = heir?.id
            if heir == nil { owner.page = .home }
        }
        return removedTabIDs
    }

    // Riordino (drag, bump) e ancora di inserimento: in `WorkspaceStore+Ordering.swift`.

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
        return workspace.insertTab(Tab(title: title, currentDirectory: inherited), select: true)
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
        // La tab non esiste più: un banner che la riapre porterebbe da nessuna parte.
        if removed != nil { onAttentionCleared?(tabID) }
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

    // Riordino delle tab e "Move to New Workspace": in `WorkspaceStore+Ordering.swift`.

    // Stato agente e marker di attenzione (applyAgentState, dismiss, decadenza): in
    // `WorkspaceStore+AgentState.swift`.
}
