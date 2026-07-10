import Foundation
import Testing
@testable import WorkspaceModel

// Albero di split (modello cmux): foglie = pane con le loro tab. Gli invarianti che reggono tutto:
// una tab sta in un pane solo, ogni pane ha almeno una tab; ogni operazione li preserva,
// `sanitized` li ripristina dopo il disco.

private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
private let branch = UUID()

private func pane(_ tabs: UUID..., selected: UUID? = nil) -> SplitPane {
    SplitPane(tabIDs: tabs, selectedTabID: selected)
}

// MARK: - SplitPane

@Test func paneSelectionDefaultsToFirstTabAndValidates() {
    #expect(pane(a, b).selectedTabID == a)
    #expect(SplitPane(tabIDs: [a, b], selectedTabID: b).selectedTabID == b)
    // Una selezione che non è del pane cade sulla prima tab.
    #expect(SplitPane(tabIDs: [a], selectedTabID: c).selectedTabID == a)
    #expect(SplitPane(tabIDs: []).selectedTabID == nil)
}

@Test func paneRemoveKeepsSelectionIndexStable() {
    // Semantica browser/bonsplit: chiusa la selezionata, si seleziona la tab che scivola nel suo
    // slot; se era l'ultima, la precedente.
    var strip = pane(a, b, c, selected: b)
    strip.remove(b)
    #expect(strip.selectedTabID == c)
    strip = pane(a, b, c, selected: c)
    strip.remove(c)
    #expect(strip.selectedTabID == b)
    // Chiudere una non selezionata non tocca la selezione.
    strip = pane(a, b, c, selected: a)
    strip.remove(c)
    #expect(strip.selectedTabID == a)
}

@Test func paneInsertAndMoveKeepOrder() {
    var strip = pane(a, b, selected: a)
    strip.insert(c, select: false)
    #expect(strip.tabIDs == [a, b, c])
    #expect(strip.selectedTabID == a) // insert senza select non ruba la selezione
    strip.insert(c) // già presente: no-op
    #expect(strip.tabIDs == [a, b, c])
    strip.move(c, before: a)
    #expect(strip.tabIDs == [c, a, b])
    strip.move(c, before: nil) // in fondo
    #expect(strip.tabIDs == [a, b, c])
    #expect(strip.selectedTabID == a) // spostare non è selezionare
}

// MARK: - Albero

@Test func panesFollowVisualOrder() {
    let root = pane(a)
    let tree = SplitNode.pane(root)
        .splitting(root.id, axis: .horizontal, with: pane(b), branchID: branch)

    #expect(tree.allTabIDs == [a, b])
    #expect(tree.visibleTabIDs == [a, b])
    #expect(tree.paneID(containing: a) == root.id)
    #expect(!tree.contains(tabID: c))
}

@Test func visibleTabsAreTheSelectedOfEachPane() {
    let root = pane(a, b, selected: b)
    let tree = SplitNode.pane(root)
        .splitting(root.id, axis: .horizontal, with: pane(c, d, selected: c), branchID: branch)

    #expect(tree.allTabIDs == [a, b, c, d])
    #expect(tree.visibleTabIDs == [b, c])
}

@Test func splittingUnknownPaneIsNoOp() {
    let tree = SplitNode.pane(pane(a))
    #expect(tree.splitting(UUID(), axis: .vertical, with: pane(b)) == tree)
}

@Test func nestedSplitKeepsBothBranches() {
    let root = pane(a)
    let second = pane(b)
    let tree = SplitNode.pane(root)
        .splitting(root.id, axis: .horizontal, with: second, branchID: branch)
        .splitting(second.id, axis: .vertical, with: pane(c), branchID: UUID())

    #expect(tree.allTabIDs == [a, b, c])
    #expect(tree.paneIDs.count == 3)
}

@Test func removingAPaneCollapsesIntoItsSibling() {
    let root = pane(a)
    let second = pane(b)
    let tree = SplitNode.pane(root)
        .splitting(root.id, axis: .horizontal, with: second, branchID: branch)

    // Tolto un pane, il fratello prende tutto lo spazio: niente ramo con un figlio solo.
    #expect(tree.removingPane(root.id) == .pane(second))
    #expect(tree.removingPane(second.id) == .pane(root))
    #expect(SplitNode.pane(root).removingPane(root.id) == nil) // era l'ultimo
}

@Test func removingATabPrunesItsPaneWhenEmpty() {
    let root = pane(a, b, selected: a)
    let second = pane(c)
    let tree = SplitNode.pane(root)
        .splitting(root.id, axis: .horizontal, with: second, branchID: branch)

    // `c` era l'unica tab del suo pane: il pane collassa.
    #expect(tree.removingTab(c) == .pane(root))
    // `a` lascia il pane vivo con `b`.
    let pruned = tree.removingTab(a)
    #expect(pruned?.allTabIDs == [b, c])
    #expect(pruned?.paneIDs.count == 2)
    // L'ultima tab dell'ultimo pane: non resta layout.
    #expect(SplitNode.pane(pane(a)).removingTab(a) == nil)
    // Una tab ignota non tocca l'albero.
    #expect(tree.removingTab(d) == tree)
}

@Test func updatingPaneRewritesContentInPlace() {
    let root = pane(a, b, selected: a)
    let tree = SplitNode.pane(root)
        .splitting(root.id, axis: .horizontal, with: pane(c), branchID: branch)

    let updated = tree.updatingPane(root.id) { $0.select(b) }
    #expect(updated.pane(root.id)?.selectedTabID == b)
    // L'identità del pane non cambia: per il rendering è la stessa struttura.
    #expect(updated.hasSameStructure(as: tree))
}

@Test func settingRatioTouchesOnlyTheTargetBranchAndClamps() {
    let root = pane(a)
    let second = pane(b)
    let inner = UUID()
    let tree = SplitNode.pane(root)
        .splitting(root.id, axis: .horizontal, with: second, branchID: branch)
        .splitting(second.id, axis: .vertical, with: pane(c), branchID: inner)

    guard case let .split(_, _, outerRatio, _, second2) = tree.settingRatio(0.8, forBranch: inner)
    else { return #expect(Bool(false), "la radice deve restare uno split") }
    #expect(outerRatio == 0.5) // il ramo esterno non si tocca
    guard case let .split(_, _, innerRatio, _, _) = second2
    else { return #expect(Bool(false), "il ramo interno deve restare uno split") }
    #expect(innerRatio == 0.8)

    // Un pane non si trascina fino a sparire.
    guard case let .split(_, _, clamped, _, _) = tree.settingRatio(0.0, forBranch: branch)
    else { return #expect(Bool(false), "la radice deve restare uno split") }
    #expect(clamped == 0.05)
}

@Test func adjacentPaneCyclesInBothDirections() {
    let first = pane(a)
    let second = pane(b)
    let third = pane(c)
    let tree = SplitNode.pane(first)
        .splitting(first.id, axis: .horizontal, with: second, branchID: branch)
        .splitting(second.id, axis: .vertical, with: third, branchID: UUID())

    #expect(tree.adjacentPaneID(to: first.id, forward: true) == second.id)
    #expect(tree.adjacentPaneID(to: third.id, forward: true) == first.id) // ciclico
    #expect(tree.adjacentPaneID(to: first.id, forward: false) == third.id)
    #expect(tree.adjacentPaneID(to: UUID(), forward: true) == nil) // ignoto
    #expect(SplitNode.pane(first).adjacentPaneID(to: first.id, forward: true) == nil) // unico
}

@Test func sanitizedDropsMissingTabsAndCollapsesEmptyPanes() {
    let root = pane(a, b, selected: b)
    let second = pane(c)
    let tree = SplitNode.pane(root)
        .splitting(root.id, axis: .horizontal, with: second, branchID: branch)

    // `c` non esiste più (tab chiusa mentre l'app era spenta): il suo pane collassa.
    let sane = tree.sanitized(keeping: [a, b])
    #expect(sane?.paneIDs == [root.id])
    #expect(sane?.pane(root.id)?.tabIDs == [a, b])
    #expect(sane?.pane(root.id)?.selectedTabID == b) // la selezione valida sopravvive
    #expect(tree.sanitized(keeping: []) == nil)
}

@Test func sanitizedDropsDuplicateTabsAcrossPanes() {
    // Un layout corrotto potrebbe ospitare la stessa tab in due pane: la prima occorrenza vince.
    let first = pane(a, b)
    let second = pane(a, c)
    let tree = SplitNode.pane(first)
        .splitting(first.id, axis: .horizontal, with: second, branchID: branch)

    let sane = tree.sanitized(keeping: [a, b, c])
    #expect(sane?.allTabIDs == [a, b, c])
    #expect(sane?.pane(second.id)?.tabIDs == [c])
}

@Test func sameStructureIgnoresRatiosAndPaneContent() {
    let root = pane(a, b, selected: a)
    let tree = SplitNode.pane(root)
        .splitting(root.id, axis: .horizontal, with: pane(c), branchID: branch)

    // Ratio diverso, selezione diversa, tab in più: stessa struttura (il rendering non
    // ricostruisce, scambia contenuti e riscrive rapporti).
    let mutated = tree.settingRatio(0.7, forBranch: branch)
        .updatingPane(root.id) { $0.select(b); $0.insert(d, select: false) }
    #expect(tree.hasSameStructure(as: mutated))
    // Un pane in più è un'altra struttura.
    let grown = tree.splitting(root.id, axis: .vertical, with: pane(d), branchID: UUID())
    #expect(!tree.hasSameStructure(as: grown))
}

// MARK: - Codable

@Test func splitNodeSurvivesACodableRoundTrip() throws {
    let root = pane(a, b, selected: b)
    let second = pane(c)
    let tree = SplitNode.pane(root)
        .splitting(root.id, axis: .horizontal, with: second, branchID: branch)
        .splitting(second.id, axis: .vertical, with: pane(d), branchID: UUID())

    let data = try JSONEncoder().encode(tree)
    let decoded = try JSONDecoder().decode(SplitNode.self, from: data)

    #expect(decoded == tree)
}

@Test func splitNodeDecodesTheLegacyTabLeafFormat() throws {
    // Il formato v1 (foglie = Tab.id, sintesi Swift: {"leaf":{"_0":uuid}}) deve decodificare come
    // pane con quella sola tab: i layout salvati prima del modello cmux sopravvivono senza bump.
    let json = """
    {"split":{"id":"\(branch.uuidString)","axis":"horizontal","ratio":0.7,
    "first":{"leaf":{"_0":"\(a.uuidString)"}},"second":{"leaf":{"_0":"\(b.uuidString)"}}}}
    """
    let decoded = try JSONDecoder().decode(SplitNode.self, from: Data(json.utf8))

    #expect(decoded.allTabIDs == [a, b])
    #expect(decoded.visibleTabIDs == [a, b]) // ogni pane seleziona la sua unica tab
    guard case let .split(id, axis, ratio, _, _) = decoded
    else { return #expect(Bool(false), "la radice deve restare uno split") }
    #expect(id == branch)
    #expect(axis == .horizontal)
    #expect(ratio == 0.7)
}
