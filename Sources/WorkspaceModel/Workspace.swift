import AgentProtocol
import Foundation

/// Un progetto: raggruppa tab (terminali), sta nella sidebar, si pinna e si riordina.
/// Model puro e osservabile: nessuna dipendenza da AppKit o dall'engine. Le surface vive sono
/// legate per `Tab.id` fuori dal model (vedi TerminalHostUI).
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
    /// La tab **focused**: quella che riceve tastiera e comandi. Con uno split è una delle montate;
    /// senza, è semplicemente l'unica mostrata.
    public var selectedTabID: UUID?
    /// Disposizione dei pane. `nil` = pane singolo (solo `selectedTab` a schermo), la forma
    /// canonica: un albero ridotto a una foglia viene sempre normalizzato a `nil`, così lo stesso
    /// stato non ha due rappresentazioni. Le foglie sono `Tab.id` di questo workspace.
    public var splitLayout: SplitNode?

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
        splitLayout: SplitNode? = nil
    ) {
        self.id = id
        self.windowID = windowID
        self.name = name
        self.nameOrigin = nameOrigin
        self.rootPath = rootPath
        self.pinned = pinned
        self.archived = archived
        self.tabs = tabs
        self.selectedTabID = selectedTabID ?? tabs.first?.id
        self.splitLayout = splitLayout
    }

    public var selectedTab: Tab? {
        tabs.first { $0.id == selectedTabID }
    }

    /// Le tab **a schermo** in questo workspace, in ordine visivo dei pane. Senza split è solo la
    /// focused. È il rimpiazzo di "la tab selezionata" ovunque conti l'essere *visibile* (ring,
    /// mark-read, protezione dalla LRU, soppressione di notifica e bump), distinto dall'essere
    /// *focused* (input da tastiera, `Cmd+K`, find).
    public var mountedTabIDs: [UUID] {
        if let splitLayout { return splitLayout.leaves }
        return selectedTabID.map { [$0] } ?? []
    }

    /// La tab è montata in un pane di questo workspace.
    public func isMounted(_ tabID: UUID) -> Bool {
        splitLayout?.contains(tabID) ?? (selectedTabID == tabID)
    }

    /// Riduce il layout alla forma canonica: un albero con una foglia sola è un pane singolo
    /// (`nil`), e la foglia rimasta diventa la focused. Da chiamare dopo ogni mutazione del layout.
    func normalizeLayout() {
        guard let layout = splitLayout else { return }
        if let single = layout.collapsedToSingleLeaf {
            splitLayout = nil
            selectedTabID = single
        } else if selectedTabID.map({ !layout.contains($0) }) ?? true {
            // La focused deve sempre essere un pane montato: se è caduta, prendi la prima foglia.
            selectedTabID = layout.leaves.first
        }
    }

    /// Il workspace ha almeno una tab che richiede attenzione: aspetta input (`needs_input`) o ha
    /// un marker di completamento aperto - `unseen` (fresco) o `pending` (visto ma non ripreso). È
    /// un **segnale**, non un criterio d'ordine: alimenta il pallino dell'header Archive (un
    /// archiviato che brilla). La posizione in lista la governa il bump reale
    /// (`WorkspaceStore.bumpWorkspaceToTop`), non questo flag.
    public var needsAttention: Bool {
        tabs.contains { $0.agentState == .needsInput || $0.attention != .none }
    }

    // MARK: - Mutazioni tab (usate dallo store; qui per tenere l'invariante di selezione)

    @discardableResult
    func appendTab(_ tab: Tab, select: Bool) -> Tab {
        tabs.append(tab)
        if select || selectedTabID == nil { mount(tab.id) }
        return tab
    }

    /// **Monta o metti a fuoco**: se la tab è già in un pane le dà solo il focus, altrimenti prende
    /// il posto di quella nel pane focused. È la semantica di ogni "seleziona questa tab" (tab bar,
    /// `Cmd+T`, notifica, dashboard): con uno split aperto, scegliere una tab non deve mai
    /// smontare il layout né mostrare una tab fuori dai pane.
    func mount(_ tabID: UUID) {
        if let layout = splitLayout, let focused = selectedTabID, !layout.contains(tabID) {
            splitLayout = layout.replacing(focused, with: tabID)
        }
        selectedTabID = tabID
        normalizeLayout()
    }

    /// Divide il pane focused e ci mette accanto (o sotto) `newTabID`, che prende il focus.
    func split(axis: SplitAxis, with newTabID: UUID) {
        guard let focused = selectedTabID else { return }
        let base = splitLayout ?? .leaf(focused) // senza split, il pane singolo è la focused
        splitLayout = base.splitting(focused, axis: axis, with: newTabID)
        selectedTabID = newTabID
        normalizeLayout()
    }

    /// Smonta il pane: la tab **resta viva** nella tab bar (e la sua sessione col lei), sparisce
    /// solo dallo schermo. No-op senza split: l'ultimo pane non si chiude, si chiude la tab.
    func unmount(_ tabID: UUID) {
        guard let layout = splitLayout, layout.contains(tabID) else { return }
        let next = layout.adjacentLeaf(to: tabID, forward: true)
        splitLayout = layout.removing(tabID)
        if selectedTabID == tabID { selectedTabID = next }
        normalizeLayout()
    }

    /// Rimuove la tab e seleziona un vicino. Ritorna l'id rimosso (per il teardown della surface).
    /// La tab esce anche dal layout: il suo pane collassa nel fratello, e se era la focused il
    /// focus passa al pane successivo (non a una tab qualunque della tab bar).
    @discardableResult
    func removeTab(_ tabID: UUID) -> UUID? {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        let nextPane = selectedTabID == tabID
            ? splitLayout?.adjacentLeaf(to: tabID, forward: true)
            : nil
        tabs.remove(at: index)
        splitLayout = splitLayout?.removing(tabID)
        if selectedTabID == tabID {
            let neighbor = tabs[safe: index] ?? tabs[safe: index - 1] ?? tabs.last
            selectedTabID = nextPane ?? neighbor?.id
        }
        normalizeLayout()
        return tabID
    }

    /// Sposta `id` immediatamente prima di `targetID` (`nil` = in fondo). No-op se coincidono o
    /// `id` non esiste. Non tocca la selezione: spostare non cambia quale tab è attiva.
    func moveTab(_ id: UUID, before targetID: UUID?) {
        tabs.move(id, before: targetID)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array where Element: Identifiable, Element.ID == UUID {
    /// Rimuove `id` e lo reinserisce **prima** di `targetID` (`nil` o assente = in fondo). No-op se
    /// `id == targetID` o `id` non c'è. Base posizionale del riordino (workspace e tab).
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
