import Foundation

/// Come sono disposti i due figli di uno split.
public enum SplitAxis: String, Codable, Equatable, Sendable {
    /// Affiancati, divider verticale ("Split Right").
    case horizontal
    /// Impilati, divider orizzontale ("Split Down").
    case vertical
}

/// Albero di split di un workspace: le foglie sono **tab** (`Tab.id`), non un'entità `Pane` sotto
/// la Tab. La Tab resta l'unità della sessione agente (`RELAY_TAB_ID` = `Tab.id`) e lo split è
/// solo un layout che la dispone: montarla in un pane non ne cambia l'identità (ARCHITECTURE).
///
/// Puro, `Codable` e senza AppKit: il rendering (NSSplitView annidate) lo fa `TerminalHostUI`
/// leggendo questo albero. Ogni `split` porta un `id` stabile, così il rendering mappa il nodo
/// alla sua view e ne riscrive il `ratio` quando trascini il divider.
///
/// Invariante: le foglie sono **uniche** (una tab sta in un pane solo). Le operazioni qui la
/// preservano; `sanitized(keeping:)` la ripristina su un albero arrivato dal disco.
public indirect enum SplitNode: Codable, Equatable, Sendable {
    case leaf(UUID)
    case split(id: UUID, axis: SplitAxis, ratio: Double, first: SplitNode, second: SplitNode)
}

public extension SplitNode {
    /// Le tab montate, da sinistra/alto a destra/basso: l'ordine visivo dei pane.
    var leaves: [UUID] {
        switch self {
        case let .leaf(id): [id]
        case let .split(_, _, _, first, second): first.leaves + second.leaves
        }
    }

    func contains(_ tabID: UUID) -> Bool {
        switch self {
        case let .leaf(id): id == tabID
        case let .split(_, _, _, first, second): first.contains(tabID) || second.contains(tabID)
        }
    }

    /// Divide il pane di `target` in due, mettendoci accanto (o sotto) `newLeaf`. No-op se `target`
    /// non è montata o `newLeaf` lo è già (l'invariante di unicità viene prima del comando).
    /// `branchID` è iniettabile per i test: in produzione un nuovo nodo nasce con un id nuovo.
    func splitting(
        _ target: UUID,
        axis: SplitAxis,
        with newLeaf: UUID,
        ratio: Double = 0.5,
        branchID: UUID = UUID()
    ) -> SplitNode {
        guard contains(target), !contains(newLeaf) else { return self }
        return inserting(target, axis: axis, newLeaf: newLeaf, ratio: ratio, branchID: branchID)
    }

    private func inserting(
        _ target: UUID,
        axis: SplitAxis,
        newLeaf: UUID,
        ratio: Double,
        branchID: UUID
    ) -> SplitNode {
        switch self {
        case let .leaf(id):
            guard id == target else { return self }
            return .split(
                id: branchID, axis: axis, ratio: ratio,
                first: .leaf(id), second: .leaf(newLeaf)
            )
        case let .split(id, nodeAxis, nodeRatio, first, second):
            return .split(
                id: id, axis: nodeAxis, ratio: nodeRatio,
                first: first.inserting(
                    target, axis: axis, newLeaf: newLeaf, ratio: ratio, branchID: branchID
                ),
                second: second.inserting(
                    target, axis: axis, newLeaf: newLeaf, ratio: ratio, branchID: branchID
                )
            )
        }
    }

    /// Smonta la tab: il pane sparisce e il **fratello prende tutto lo spazio** (il ramo collassa).
    /// `nil` quando era l'ultima foglia, cioè non resta layout da mostrare.
    func removing(_ tabID: UUID) -> SplitNode? {
        switch self {
        case let .leaf(id):
            return id == tabID ? nil : self
        case let .split(id, axis, ratio, first, second):
            let newFirst = first.removing(tabID)
            let newSecond = second.removing(tabID)
            switch (newFirst, newSecond) {
            case (nil, nil): return nil
            case let (node?, nil): return node
            case let (nil, node?): return node
            case let (a?, b?):
                return .split(id: id, axis: axis, ratio: ratio, first: a, second: b)
            }
        }
    }

    /// Sostituisce la tab montata in un pane con un'altra, lasciando il layout intatto: è ciò che
    /// succede quando selezioni dalla tab bar una tab non montata (prende il posto di quella
    /// focused). No-op se `old` non è montata o `new` lo è già.
    func replacing(_ old: UUID, with new: UUID) -> SplitNode {
        guard contains(old), !contains(new) else { return self }
        switch self {
        case let .leaf(id):
            return id == old ? .leaf(new) : self
        case let .split(id, axis, ratio, first, second):
            return .split(
                id: id, axis: axis, ratio: ratio,
                first: first.replacing(old, with: new),
                second: second.replacing(old, with: new)
            )
        }
    }

    /// Nuovo rapporto di divisione del nodo (drag del divider). `ratio` è la quota del **primo**
    /// figlio, clampata a `0.05...0.95`: un pane non si può ridurre a niente col trascinamento.
    func settingRatio(_ newRatio: Double, forBranch branchID: UUID) -> SplitNode {
        switch self {
        case .leaf:
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

    /// La foglia successiva (o precedente) a `tabID` nell'ordine visivo, ciclica: guida il ciclo
    /// del focus fra i pane. `nil` se `tabID` non è montata o è l'unica.
    func adjacentLeaf(to tabID: UUID, forward: Bool) -> UUID? {
        let all = leaves
        guard all.count > 1, let index = all.firstIndex(of: tabID) else { return nil }
        let next = (index + (forward ? 1 : -1) + all.count) % all.count
        return all[next]
    }

    /// Ricostruisce l'albero tenendo solo le foglie ancora esistenti e scartando i duplicati. Serve
    /// al restore: un layout sul disco può puntare a tab sparite (o ripetute, se il file è stato
    /// toccato a mano), e un pane senza tab non è renderizzabile. `nil` = niente da mostrare, il
    /// workspace torna a pane singolo.
    func sanitized(keeping validTabIDs: Set<UUID>) -> SplitNode? {
        var seen: Set<UUID> = []
        return pruned(validTabIDs, &seen)
    }

    private func pruned(_ valid: Set<UUID>, _ seen: inout Set<UUID>) -> SplitNode? {
        switch self {
        case let .leaf(id):
            guard valid.contains(id), seen.insert(id).inserted else { return nil }
            return self
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

    /// Un albero ridotto a una sola foglia non è uno split: il workspace lo rappresenta come
    /// `splitLayout == nil` (pane singolo), così esiste una sola forma per lo stesso stato.
    var collapsedToSingleLeaf: UUID? {
        if case let .leaf(id) = self { return id }
        return nil
    }

    /// Stessa forma (nodi, assi, tab montate) a meno dei `ratio`. Il rendering la usa per **non**
    /// ricostruire le view mentre trascini un divider: lì cambiano solo le proporzioni, e rifare
    /// l'albero di view sotto il puntatore darebbe flicker e perdita di focus.
    func hasSameStructure(as other: SplitNode) -> Bool {
        switch (self, other) {
        case let (.leaf(a), .leaf(b)):
            a == b
        case let (.split(idA, axisA, _, firstA, secondA), .split(idB, axisB, _, firstB, secondB)):
            idA == idB && axisA == axisB
                && firstA.hasSameStructure(as: firstB)
                && secondA.hasSameStructure(as: secondB)
        default:
            false
        }
    }
}
