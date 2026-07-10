import AgentProtocol
import Foundation

/// Un progetto: raggruppa tab (terminali), sta nella sidebar, si pinna e si riordina.
/// Model puro e osservabile: nessuna dipendenza da AppKit o dall'engine. Le surface vive sono
/// legate per `Tab.id` fuori dal model (vedi TerminalHostUI).
///
/// Le tab vivono **nei pane** (`layout`, modello cmux): ogni pane ha la sua lista ordinata e la
/// sua selezione. `tabs` è il sacco degli oggetti `Tab` (identità e sessione agente); l'ordine
/// visivo sta nel layout. Invariante: l'unione dei `tabIDs` dei pane = gli id di `tabs`.
@Observable
public final class Workspace: Identifiable {
    public let id: UUID
    /// La finestra che possiede il workspace: le finestre partizionano i workspace, non li
    /// condividono (una surface sta in una view sola). Muterla lo sposta di finestra.
    public var windowID: UUID
    public var name: String
    /// Origine del nome (vedi `NameOrigin`): guida la nomina automatica. `.default` = eleggibile,
    /// `.generated` = già nominato (one-shot), `.user` = rinominato a mano (intoccabile).
    public var nameOrigin: NameOrigin
    public var rootPath: String?
    public var pinned: Bool
    /// Messo via: fuori dalla lista principale, raccolto nella sezione Archive in fondo alla
    /// sidebar. Mutuamente esclusivo con `pinned` (tenere in cima vs mettere via) e con il float
    /// per attenzione (gli archiviati non galleggiano).
    public var archived: Bool
    public private(set) var tabs: [Tab]
    /// Disposizione dei pane, **sempre presente**: il pane singolo è un `.pane` con tutte le tab,
    /// non un caso speciale. Le foglie sono `SplitPane` (tab ordinate + selezione per pane).
    public private(set) var layout: SplitNode
    /// Il pane **focused**: la sua tab selezionata riceve tastiera e comandi.
    public private(set) var focusedPaneID: UUID

    public init(
        id: UUID = UUID(),
        windowID: UUID = RelayWindow.mainID,
        name: String,
        nameOrigin: NameOrigin = .user,
        rootPath: String? = nil,
        pinned: Bool = false,
        archived: Bool = false,
        tabs: [Tab] = [],
        selectedTabID: UUID? = nil,
        layout: SplitNode? = nil,
        focusedPaneID: UUID? = nil
    ) {
        self.id = id
        self.windowID = windowID
        self.name = name
        self.nameOrigin = nameOrigin
        self.rootPath = rootPath
        self.pinned = pinned
        self.archived = archived
        self.tabs = tabs
        // Il layout passato (restore) viene sanitizzato contro le tab reali; le tab rimaste fuori
        // vengono adottate. Senza layout: un pane radice con tutte le tab.
        let normalized = Self.normalizedLayout(
            layout, tabs: tabs, selectedTabID: selectedTabID
        )
        self.layout = normalized
        let paneIDs = normalized.paneIDs
        let focusCandidate = focusedPaneID.flatMap { paneIDs.contains($0) ? $0 : nil }
        let selectionPane = selectedTabID.flatMap { normalized.paneID(containing: $0) }
        self.focusedPaneID = focusCandidate ?? selectionPane ?? paneIDs[0]
        if let selectedTabID {
            self.layout = normalized.updatingPane(self.focusedPaneID) { $0.select(selectedTabID) }
        }
    }

    /// Sanitizza un layout arrivato dal restore e adotta le tab che ne restano fuori (snapshot
    /// vecchi o file toccati a mano): finiscono nel pane della selezione, in coda alla strip.
    private static func normalizedLayout(
        _ layout: SplitNode?, tabs: [Tab], selectedTabID: UUID?
    ) -> SplitNode {
        let valid = Set(tabs.map(\.id))
        guard let layout, let sane = layout.sanitized(keeping: valid) else {
            return .pane(SplitPane(tabIDs: tabs.map(\.id), selectedTabID: selectedTabID))
        }
        let known = Set(sane.allTabIDs)
        let orphans = tabs.map(\.id).filter { !known.contains($0) }
        guard !orphans.isEmpty else { return sane }
        let home = selectedTabID.flatMap { sane.paneID(containing: $0) } ?? sane.paneIDs[0]
        return sane.updatingPane(home) { pane in
            for orphan in orphans {
                pane.insert(orphan, select: false)
            }
        }
    }

    // MARK: - Selezione e visibilità

    /// La tab **focused**: la selezione del pane focused. Derivata dal layout: per mutarla passa
    /// da `reveal` (seleziona nel suo pane + focus al pane).
    public var selectedTabID: UUID? {
        layout.pane(focusedPaneID)?.selectedTabID
    }

    public var selectedTab: Tab? {
        tabs.first { $0.id == selectedTabID }
    }

    public var focusedPane: SplitPane? {
        layout.pane(focusedPaneID)
    }

    /// Le tab **a schermo** (la selezionata di ogni pane), in ordine visivo. È il criterio ovunque
    /// conti l'essere *visibile* (ring, mark-read, protezione dalla LRU, soppressione di notifica
    /// e bump), distinto dall'essere *focused* (input da tastiera, `Cmd+K`, find).
    public var visibleTabIDs: [UUID] {
        layout.visibleTabIDs
    }

    /// La tab è a schermo in un pane di questo workspace.
    public func isVisible(_ tabID: UUID) -> Bool {
        layout.visibleTabIDs.contains(tabID)
    }

    /// Le tab del workspace nell'ordine visivo dei pane (per navigazione e dashboard).
    public var orderedTabs: [Tab] {
        layout.allTabIDs.compactMap { id in tabs.first { $0.id == id } }
    }

    public func tab(_ tabID: UUID) -> Tab? {
        tabs.first { $0.id == tabID }
    }

    /// Il workspace ha almeno una tab che richiede attenzione: aspetta input (`needs_input`) o ha
    /// un marker di completamento aperto - `unseen` (fresco) o `pending` (visto ma non ripreso). È
    /// un **segnale**, non un criterio d'ordine: alimenta il pallino dell'header Archive (un
    /// archiviato che brilla). La posizione in lista la governa il bump reale
    /// (`WorkspaceStore.bumpWorkspaceToTop`), non questo flag.
    public var needsAttention: Bool {
        tabs.contains { $0.agentState == .needsInput || $0.attention != .none }
    }

    // MARK: - Mutazioni (usate dallo store; qui per tenere gli invarianti)

    /// Aggiunge una tab al pane focused, in fondo alla sua strip.
    @discardableResult
    func appendTab(_ tab: Tab, select: Bool) -> Tab {
        tabs.append(tab)
        layout = layout.updatingPane(focusedPaneID) { $0.insert(tab.id, select: select) }
        return tab
    }

    /// **Rivela** una tab: la seleziona nel suo pane e dà il focus a quel pane. È la semantica di
    /// ogni "seleziona questa tab" (strip, notifica, dashboard, `Cmd+J`): selezionare non muta mai
    /// la struttura dei pane.
    func reveal(_ tabID: UUID) {
        guard let owner = layout.paneID(containing: tabID) else { return }
        layout = layout.updatingPane(owner) { $0.select(tabID) }
        focusedPaneID = owner
    }

    /// Dà il focus a un pane esistente, senza toccare le selezioni.
    func focusPane(_ paneID: UUID) {
        guard layout.pane(paneID) != nil else { return }
        focusedPaneID = paneID
    }

    /// Divide un pane (default il focused) con una **tab nuova**: entra in `tabs` e diventa
    /// l'unica tab del nuovo pane, che prende il focus.
    func splitPane(_ paneID: UUID? = nil, axis: SplitAxis, adding tab: Tab) {
        let target = paneID.flatMap { layout.pane($0) != nil ? $0 : nil } ?? focusedPaneID
        guard !layout.contains(tabID: tab.id) else { return }
        tabs.append(tab)
        let newPane = SplitPane(tabIDs: [tab.id])
        layout = layout.splitting(target, axis: axis, with: newPane)
        focusedPaneID = newPane.id
    }

    /// Sposta una tab **esistente** in un nuovo pane accanto al suo ("Open in Split", semantica
    /// bonsplit: il target è il pane della tab): lascia la strip e vive da sola nel nuovo pane,
    /// che prende il focus. No-op se è l'unica tab del suo pane: dividerla accanto a sé stessa
    /// non produce niente.
    func moveTabToSplit(_ tabID: UUID, axis: SplitAxis) {
        guard let owner = layout.paneID(containing: tabID),
              layout.pane(owner).map({ $0.tabIDs.count > 1 }) == true,
              let removed = layout.removingTab(tabID) else { return }
        let newPane = SplitPane(tabIDs: [tabID])
        layout = removed.splitting(owner, axis: axis, with: newPane)
        focusedPaneID = newPane.id
    }

    /// Chiude un pane: le sue tab **muoiono con lui** (il chiamante fa il teardown delle surface e
    /// la conferma sui processi in foreground). Il fratello prende lo spazio e il focus. No-op
    /// sull'ultimo pane (si chiude il workspace, non il pane). Ritorna gli id delle tab rimosse.
    @discardableResult
    func closePane(_ paneID: UUID) -> [UUID] {
        guard layout.paneIDs.count > 1, let pane = layout.pane(paneID) else { return [] }
        let heir = layout.adjacentPaneID(to: paneID, forward: true)
        guard let remaining = layout.removingPane(paneID) else { return [] }
        let removed = pane.tabIDs
        tabs.removeAll { removed.contains($0.id) }
        layout = remaining
        if focusedPaneID == paneID {
            focusedPaneID = heir.flatMap { remaining.pane($0) != nil ? $0 : nil }
                ?? remaining.paneIDs[0]
        }
        return removed
    }

    /// Rimuove la tab dal workspace e dal suo pane; un pane rimasto vuoto collassa nel fratello.
    /// La selezione dentro il pane resta stabile per indice (vedi `SplitPane.remove`); se il pane
    /// muore, il focus passa al vicino. Ritorna l'id rimosso (per il teardown della surface).
    @discardableResult
    func removeTab(_ tabID: UUID) -> UUID? {
        guard tabs.contains(where: { $0.id == tabID }) else { return nil }
        let owner = layout.paneID(containing: tabID)
        let heir = owner.flatMap { layout.adjacentPaneID(to: $0, forward: true) }
        tabs.removeAll { $0.id == tabID }
        guard let remaining = layout.removingTab(tabID) else {
            // Ultima tab dell'ultimo pane: il workspace sta per chiudere (cascade nello store),
            // ma il layout resta valido con un pane vuoto per non violare l'invariante.
            layout = .pane(SplitPane(id: focusedPaneID, tabIDs: []))
            return tabID
        }
        layout = remaining
        if remaining.pane(focusedPaneID) == nil {
            focusedPaneID = heir.flatMap { remaining.pane($0) != nil ? $0 : nil }
                ?? remaining.paneIDs[0]
        }
        return tabID
    }

    /// Sposta `id` immediatamente prima di `targetID` **nella strip del suo pane** (`nil` = in
    /// fondo). No-op se le due tab vivono in pane diversi: il riordino cross-pane è un drag
    /// futuro, non questo. Non tocca la selezione: spostare non cambia quale tab è attiva.
    func moveTab(_ id: UUID, before targetID: UUID?) {
        guard let owner = layout.paneID(containing: id) else { return }
        if let targetID, layout.pane(owner)?.contains(targetID) != true { return }
        layout = layout.updatingPane(owner) { $0.move(id, before: targetID) }
    }

    /// Nuovo rapporto di divisione di un nodo (drag del divider).
    func setRatio(_ ratio: Double, forBranch branchID: UUID) {
        layout = layout.settingRatio(ratio, forBranch: branchID)
    }

    /// Adotta una tab creata fuori dal layout (restore di casi limite). Interno al modulo.
    func adoptTab(_ tab: Tab, inPane paneID: UUID? = nil, select: Bool = false) {
        guard !layout.contains(tabID: tab.id) else { return }
        if !tabs.contains(where: { $0.id == tab.id }) { tabs.append(tab) }
        let home = paneID.flatMap { layout.pane($0) != nil ? $0 : nil } ?? focusedPaneID
        layout = layout.updatingPane(home) { $0.insert(tab.id, select: select) }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element: Identifiable, Element.ID == UUID {
    /// Rimuove `id` e lo reinserisce **prima** di `targetID` (`nil` o assente = in fondo). No-op se
    /// `id == targetID` o `id` non c'è. Base posizionale del riordino dei workspace.
    mutating func move(_ id: UUID, before targetID: UUID?) {
        guard id != targetID, let from = firstIndex(where: { $0.id == id }) else { return }
        let moved = remove(at: from)
        if let targetID, let to = firstIndex(where: { $0.id == targetID }) {
            insert(moved, at: to)
        } else {
            append(moved)
        }
    }

    /// Come `move(_:before:)` ma reinserisce **dopo** `targetID` (`targetID` assente = in fondo).
    mutating func move(_ id: UUID, after targetID: UUID) {
        guard id != targetID, let from = firstIndex(where: { $0.id == id }) else { return }
        let moved = remove(at: from)
        if let to = firstIndex(where: { $0.id == targetID }) {
            insert(moved, at: to + 1)
        } else {
            append(moved)
        }
    }
}
