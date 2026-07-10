import Foundation

/// Come sono disposti i due figli di uno split.
public enum SplitAxis: String, Codable, Equatable, Sendable {
    /// Affiancati, divider verticale ("Split Right").
    case horizontal
    /// Impilati, divider orizzontale ("Split Down").
    case vertical
}

/// Un pane: una porzione di schermo con la **sua** lista ordinata di tab e la sua selezione
/// (modello cmux/bonsplit). La tab selezionata è quella a schermo; le altre vivono nella strip del
/// pane. La `Tab` resta l'unità della sessione agente (`RELAY_TAB_ID` = `Tab.id`): il pane la
/// ospita, non la possiede - spostarla non ne tocca identità né surface.
public struct SplitPane: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public private(set) var tabIDs: [UUID]
    public private(set) var selectedTabID: UUID?

    public init(id: UUID = UUID(), tabIDs: [UUID], selectedTabID: UUID? = nil) {
        self.id = id
        self.tabIDs = tabIDs
        let candidate = selectedTabID.flatMap { tabIDs.contains($0) ? $0 : nil }
        self.selectedTabID = candidate ?? tabIDs.first
    }

    public var isEmpty: Bool {
        tabIDs.isEmpty
    }

    public func contains(_ tabID: UUID) -> Bool {
        tabIDs.contains(tabID)
    }

    /// Seleziona una tab del pane. No-op se non è sua.
    mutating func select(_ tabID: UUID) {
        guard tabIDs.contains(tabID) else { return }
        selectedTabID = tabID
    }

    /// Inserisce una tab (`index` `nil` = in fondo). No-op se è già nel pane.
    mutating func insert(_ tabID: UUID, at index: Int? = nil, select: Bool = true) {
        guard !tabIDs.contains(tabID) else { return }
        let position = index.map { min(max(0, $0), tabIDs.count) } ?? tabIDs.count
        tabIDs.insert(tabID, at: position)
        if select || selectedTabID == nil { selectedTabID = tabID }
    }

    /// Rimuove una tab. Se era la selezionata, la selezione resta stabile per **indice** (la tab
    /// che scivola nel suo slot), con fallback alla precedente quando era l'ultima - la semantica
    /// dei browser e di bonsplit.
    mutating func remove(_ tabID: UUID) {
        guard let index = tabIDs.firstIndex(of: tabID) else { return }
        tabIDs.remove(at: index)
        if selectedTabID == tabID {
            selectedTabID = tabIDs.isEmpty ? nil : tabIDs[min(index, tabIDs.count - 1)]
        }
    }

    /// Sposta `tabID` immediatamente prima di `targetID` (`nil` = in fondo). Non tocca la
    /// selezione: spostare non è selezionare.
    mutating func move(_ tabID: UUID, before targetID: UUID?) {
        guard tabID != targetID, let from = tabIDs.firstIndex(of: tabID) else { return }
        tabIDs.remove(at: from)
        if let targetID, let to = tabIDs.firstIndex(of: targetID) {
            tabIDs.insert(tabID, at: to)
        } else {
            tabIDs.append(tabID)
        }
    }
}

/// Albero di split di un workspace: le foglie sono **pane** (`SplitPane`), ognuno con le sue tab
/// (modello cmux). Ogni workspace ne ha sempre uno: il pane singolo è `.pane` con tutte le tab,
/// non un caso speciale.
///
/// Puro, `Codable` e senza AppKit: il rendering (NSSplitView annidate) lo fa `TerminalHostUI`
/// leggendo questo albero. Ogni `split` porta un `id` stabile, così il rendering mappa il nodo
/// alla sua view e ne riscrive il `ratio` quando trascini il divider.
///
/// Invariante: una tab sta in **un pane solo** e ogni pane ha almeno una tab. Le operazioni qui la
/// preservano; `sanitized(keeping:)` la ripristina su un albero arrivato dal disco.
public indirect enum SplitNode: Equatable, Sendable {
    case pane(SplitPane)
    case split(id: UUID, axis: SplitAxis, ratio: Double, first: SplitNode, second: SplitNode)
}

public extension SplitNode {
    /// I pane da sinistra/alto a destra/basso: l'ordine visivo.
    var panes: [SplitPane] {
        switch self {
        case let .pane(pane): [pane]
        case let .split(_, _, _, first, second): first.panes + second.panes
        }
    }

    var paneIDs: [UUID] {
        panes.map(\.id)
    }

    /// Tutte le tab del workspace nell'ordine visivo dei pane.
    var allTabIDs: [UUID] {
        panes.flatMap(\.tabIDs)
    }

    /// Le tab **a schermo**: la selezionata di ogni pane, in ordine visivo.
    var visibleTabIDs: [UUID] {
        panes.compactMap(\.selectedTabID)
    }

    func pane(_ paneID: UUID) -> SplitPane? {
        panes.first { $0.id == paneID }
    }

    /// Il pane che ospita la tab, se esiste.
    func paneID(containing tabID: UUID) -> UUID? {
        panes.first { $0.contains(tabID) }?.id
    }

    func contains(tabID: UUID) -> Bool {
        paneID(containing: tabID) != nil
    }

    /// Riscrive un pane applicandogli `transform`. L'identità del pane non cambia: il rendering
    /// non vede un cambio di struttura, solo di contenuto.
    func updatingPane(_ paneID: UUID, _ transform: (inout SplitPane) -> Void) -> SplitNode {
        switch self {
        case var .pane(pane):
            guard pane.id == paneID else { return self }
            transform(&pane)
            return .pane(pane)
        case let .split(id, axis, ratio, first, second):
            return .split(
                id: id, axis: axis, ratio: ratio,
                first: first.updatingPane(paneID, transform),
                second: second.updatingPane(paneID, transform)
            )
        }
    }

    /// Divide il pane `target` in due: lui resta primo (sinistra/alto), `newPane` arriva secondo.
    /// No-op se `target` non esiste. `branchID` è iniettabile per i test: in produzione un nuovo
    /// nodo nasce con un id nuovo.
    func splitting(
        _ target: UUID,
        axis: SplitAxis,
        with newPane: SplitPane,
        ratio: Double = 0.5,
        branchID: UUID = UUID()
    ) -> SplitNode {
        switch self {
        case let .pane(pane):
            guard pane.id == target else { return self }
            return .split(
                id: branchID, axis: axis, ratio: ratio,
                first: .pane(pane), second: .pane(newPane)
            )
        case let .split(id, nodeAxis, nodeRatio, first, second):
            return .split(
                id: id, axis: nodeAxis, ratio: nodeRatio,
                first: first.splitting(
                    target,
                    axis: axis,
                    with: newPane,
                    ratio: ratio,
                    branchID: branchID
                ),
                second: second.splitting(
                    target,
                    axis: axis,
                    with: newPane,
                    ratio: ratio,
                    branchID: branchID
                )
            )
        }
    }

    /// Rimuove il pane: il **fratello prende tutto lo spazio** (il ramo collassa). `nil` quando era
    /// l'ultimo, cioè non resta layout da mostrare.
    func removingPane(_ paneID: UUID) -> SplitNode? {
        switch self {
        case let .pane(pane):
            return pane.id == paneID ? nil : self
        case let .split(id, axis, ratio, first, second):
            let newFirst = first.removingPane(paneID)
            let newSecond = second.removingPane(paneID)
            switch (newFirst, newSecond) {
            case (nil, nil): return nil
            case let (node?, nil): return node
            case let (nil, node?): return node
            case let (a?, b?):
                return .split(id: id, axis: axis, ratio: ratio, first: a, second: b)
            }
        }
    }

    /// Rimuove una tab dal suo pane; un pane rimasto vuoto collassa nel fratello. `nil` quando era
    /// l'ultima tab dell'ultimo pane.
    func removingTab(_ tabID: UUID) -> SplitNode? {
        guard let owner = paneID(containing: tabID) else { return self }
        let updated = updatingPane(owner) { $0.remove(tabID) }
        if updated.pane(owner)?.isEmpty == true {
            return updated.removingPane(owner)
        }
        return updated
    }

    /// Nuovo rapporto di divisione del nodo (drag del divider). `ratio` è la quota del **primo**
    /// figlio, clampata a `0.05...0.95`: un pane non si può ridurre a niente col trascinamento.
    func settingRatio(_ newRatio: Double, forBranch branchID: UUID) -> SplitNode {
        switch self {
        case .pane:
            return self
        case let .split(id, axis, ratio, first, second):
            let updated = id == branchID ? min(max(newRatio, 0.05), 0.95) : ratio
            return .split(
                id: id, axis: axis, ratio: updated,
                first: first.settingRatio(newRatio, forBranch: branchID),
                second: second.settingRatio(newRatio, forBranch: branchID)
            )
        }
    }

    /// Il pane successivo (o precedente) nell'ordine visivo, ciclico: guida `Cmd+]`/`Cmd+[`.
    /// `nil` se `paneID` non esiste o è l'unico.
    func adjacentPaneID(to paneID: UUID, forward: Bool) -> UUID? {
        let all = paneIDs
        guard all.count > 1, let index = all.firstIndex(of: paneID) else { return nil }
        let next = (index + (forward ? 1 : -1) + all.count) % all.count
        return all[next]
    }

    /// Ricostruisce l'albero tenendo solo le tab ancora esistenti, scartando i duplicati (la prima
    /// occorrenza vince) e collassando i pane rimasti vuoti. Serve al restore: un layout sul disco
    /// può puntare a tab sparite o ripetute. `nil` = nessun pane con tab, il chiamante riparte da
    /// un pane radice.
    func sanitized(keeping validTabIDs: Set<UUID>) -> SplitNode? {
        var seen: Set<UUID> = []
        return pruned(validTabIDs, &seen)
    }

    private func pruned(_ valid: Set<UUID>, _ seen: inout Set<UUID>) -> SplitNode? {
        switch self {
        case let .pane(pane):
            let kept = pane.tabIDs.filter { valid.contains($0) && seen.insert($0).inserted }
            guard !kept.isEmpty else { return nil }
            return .pane(SplitPane(id: pane.id, tabIDs: kept, selectedTabID: pane.selectedTabID))
        case let .split(id, axis, ratio, first, second):
            let newFirst = first.pruned(valid, &seen)
            let newSecond = second.pruned(valid, &seen)
            switch (newFirst, newSecond) {
            case (nil, nil): return nil
            case let (node?, nil): return node
            case let (nil, node?): return node
            case let (a?, b?):
                return .split(id: id, axis: axis, ratio: ratio, first: a, second: b)
            }
        }
    }

    /// Stessa forma (branch, assi, **pane**) a meno dei `ratio` e del contenuto dei pane. Il
    /// rendering la usa per **non** ricostruire le view quando cambiano solo proporzioni, selezione
    /// o tab dentro un pane: lì si scambia il contenuto, non l'albero.
    func hasSameStructure(as other: SplitNode) -> Bool {
        switch (self, other) {
        case let (.pane(a), .pane(b)):
            a.id == b.id
        case let (.split(idA, axisA, _, firstA, secondA), .split(idB, axisB, _, firstB, secondB)):
            idA == idB && axisA == axisB
                && firstA.hasSameStructure(as: firstB)
                && secondA.hasSameStructure(as: secondB)
        default:
            false
        }
    }
}

// MARK: - Codable (compatibile col formato v1 su disco)

/// Il formato v1 aveva foglie-tab (`case leaf(UUID)`, chiave `leaf`/`_0` della sintesi Swift):
/// decodifica come pane con quella sola tab, così i layout salvati prima del modello cmux
/// sopravvivono senza bump di versione. In scrittura esiste solo il formato nuovo.
extension SplitNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case pane, split, leaf
    }

    private enum LeafKeys: String, CodingKey {
        case value = "_0"
    }

    private enum SplitKeys: String, CodingKey {
        case id, axis, ratio, first, second
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.pane) {
            self = try .pane(container.decode(SplitPane.self, forKey: .pane))
        } else if container.contains(.leaf) {
            let leaf = try container.nestedContainer(keyedBy: LeafKeys.self, forKey: .leaf)
            let tabID = try leaf.decode(UUID.self, forKey: .value)
            self = .pane(SplitPane(tabIDs: [tabID]))
        } else {
            let split = try container.nestedContainer(keyedBy: SplitKeys.self, forKey: .split)
            self = try .split(
                id: split.decode(UUID.self, forKey: .id),
                axis: split.decode(SplitAxis.self, forKey: .axis),
                ratio: split.decode(Double.self, forKey: .ratio),
                first: split.decode(SplitNode.self, forKey: .first),
                second: split.decode(SplitNode.self, forKey: .second)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .pane(pane):
            try container.encode(pane, forKey: .pane)
        case let .split(id, axis, ratio, first, second):
            var split = container.nestedContainer(keyedBy: SplitKeys.self, forKey: .split)
            try split.encode(id, forKey: .id)
            try split.encode(axis, forKey: .axis)
            try split.encode(ratio, forKey: .ratio)
            try split.encode(first, forKey: .first)
            try split.encode(second, forKey: .second)
        }
    }
}
