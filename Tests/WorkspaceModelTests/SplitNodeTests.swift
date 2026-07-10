import Foundation
import Testing
@testable import WorkspaceModel

// Albero di split: foglie = Tab.id. L'invariante che regge tutto è l'unicità delle foglie (una tab
// sta in un pane solo); ogni operazione la preserva, `sanitized` la ripristina dopo il disco.

private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
private let branch = UUID()

@Test func leavesFollowVisualOrder() {
    let tree = SplitNode.leaf(a)
        .splitting(a, axis: .horizontal, with: b, branchID: branch)

    #expect(tree.leaves == [a, b])
    #expect(tree.contains(a) && tree.contains(b))
    #expect(!tree.contains(c))
}

@Test func splittingUnknownTabIsNoOp() {
    let tree = SplitNode.leaf(a)
    #expect(tree.splitting(c, axis: .vertical, with: b) == tree)
}

@Test func splittingWithAnAlreadyMountedTabIsNoOp() {
    // Unicità delle foglie: la stessa tab non può occupare due pane (una surface, una view).
    let tree = SplitNode.leaf(a).splitting(a, axis: .horizontal, with: b, branchID: branch)
    #expect(tree.splitting(a, axis: .vertical, with: b) == tree)
}

@Test func nestedSplitKeepsBothBranches() {
    let tree = SplitNode.leaf(a)
        .splitting(a, axis: .horizontal, with: b, branchID: branch)
        .splitting(b, axis: .vertical, with: c, branchID: UUID())

    #expect(tree.leaves == [a, b, c])
}

@Test func removingALeafCollapsesIntoItsSibling() {
    let tree = SplitNode.leaf(a).splitting(a, axis: .horizontal, with: b, branchID: branch)

    // Tolto `a`, il fratello prende tutto lo spazio: niente ramo con un figlio solo.
    #expect(tree.removing(a) == .leaf(b))
    #expect(tree.removing(b) == .leaf(a))
}

@Test func removingTheLastLeafLeavesNoLayout() {
    #expect(SplitNode.leaf(a).removing(a) == nil)
}

@Test func removingAnUnknownLeafKeepsTheTree() {
    let tree = SplitNode.leaf(a).splitting(a, axis: .horizontal, with: b, branchID: branch)
    #expect(tree.removing(c) == tree)
}

@Test func removingFromANestedTreeKeepsTheRest() {
    let tree = SplitNode.leaf(a)
        .splitting(a, axis: .horizontal, with: b, branchID: branch)
        .splitting(b, axis: .vertical, with: c, branchID: UUID())

    #expect(tree.removing(b)?.leaves == [a, c])
    #expect(tree.removing(c)?.leaves == [a, b])
}

@Test func replacingSwapsTheMountedTabInPlace() {
    // Selezionare dalla tab bar una tab non montata: prende il posto di quella focused.
    let tree = SplitNode.leaf(a).splitting(a, axis: .horizontal, with: b, branchID: branch)

    #expect(tree.replacing(b, with: c).leaves == [a, c])
}

@Test func replacingIsNoOpWhenTheTargetIsMissingOrTheNewTabIsMounted() {
    let tree = SplitNode.leaf(a).splitting(a, axis: .horizontal, with: b, branchID: branch)

    #expect(tree.replacing(c, with: d) == tree) // `c` non è montata
    #expect(tree.replacing(a, with: b) == tree) // `b` lo è già: creerebbe un duplicato
}

@Test func settingRatioTouchesOnlyTheTargetBranchAndClamps() {
    let inner = UUID()
    let tree = SplitNode.leaf(a)
        .splitting(a, axis: .horizontal, with: b, branchID: branch)
        .splitting(b, axis: .vertical, with: c, branchID: inner)

    guard case let .split(_, _, outerRatio, _, second) = tree.settingRatio(0.8, forBranch: inner)
    else { return #expect(Bool(false), "la radice deve restare uno split") }
    #expect(outerRatio == 0.5) // il ramo esterno non si tocca
    guard case let .split(_, _, innerRatio, _, _) = second
    else { return #expect(Bool(false), "il ramo interno deve restare uno split") }
    #expect(innerRatio == 0.8)

    // Un pane non si trascina fino a sparire.
    guard case let .split(_, _, clamped, _, _) = tree.settingRatio(0.0, forBranch: branch)
    else { return #expect(Bool(false), "la radice deve restare uno split") }
    #expect(clamped == 0.05)
}

@Test func adjacentLeafCyclesInBothDirections() {
    let tree = SplitNode.leaf(a)
        .splitting(a, axis: .horizontal, with: b, branchID: branch)
        .splitting(b, axis: .vertical, with: c, branchID: UUID())

    #expect(tree.adjacentLeaf(to: a, forward: true) == b)
    #expect(tree.adjacentLeaf(to: c, forward: true) == a) // ciclico
    #expect(tree.adjacentLeaf(to: a, forward: false) == c)
    #expect(tree.adjacentLeaf(to: d, forward: true) == nil) // non montata
    #expect(SplitNode.leaf(a).adjacentLeaf(to: a, forward: true) == nil) // unico pane
}

@Test func sanitizedDropsMissingTabsAndCollapses() {
    let tree = SplitNode.leaf(a).splitting(a, axis: .horizontal, with: b, branchID: branch)

    // `b` non esiste più (tab chiusa mentre l'app era spenta, o layout editato a mano).
    #expect(tree.sanitized(keeping: [a]) == .leaf(a))
    #expect(tree.sanitized(keeping: []) == nil)
    #expect(tree.sanitized(keeping: [a, b]) == tree)
}

@Test func sanitizedDropsDuplicateLeaves() {
    // Un layout corrotto potrebbe montare la stessa tab due volte: la seconda occorrenza cade.
    let duplicated = SplitNode.split(
        id: branch, axis: .horizontal, ratio: 0.5, first: .leaf(a), second: .leaf(a)
    )
    #expect(duplicated.sanitized(keeping: [a]) == .leaf(a))
}

@Test func collapsedToSingleLeafIdentifiesTheSinglePaneForm() {
    #expect(SplitNode.leaf(a).collapsedToSingleLeaf == a)
    let tree = SplitNode.leaf(a).splitting(a, axis: .horizontal, with: b, branchID: branch)
    #expect(tree.collapsedToSingleLeaf == nil)
}

@Test func splitNodeSurvivesACodableRoundTrip() throws {
    let tree = SplitNode.leaf(a)
        .splitting(a, axis: .horizontal, with: b, branchID: branch)
        .splitting(b, axis: .vertical, with: c, branchID: UUID())

    let data = try JSONEncoder().encode(tree)
    let decoded = try JSONDecoder().decode(SplitNode.self, from: data)

    #expect(decoded == tree)
}
