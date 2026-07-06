import Foundation
@testable import Panels
import Testing

// La logica pura di drop della sidebar: regioni di pin, ancore di segmento (pinned/resto), no-op.
// Copre i buchi che il vecchio clamp di segmento lasciava (blocco da 1 elemento = drag morto).

private func row(_ id: UUID, pinned: Bool = false) -> SidebarDrop.Row {
    SidebarDrop.Row(id: id, pinned: pinned)
}

private let a = UUID()
private let b = UUID()
private let c = UUID()
private let d = UUID()

@Test func dropInOwnSlotIsNoOp() {
    let rows = [row(a), row(b), row(c)]
    #expect(SidebarDrop.resolve(rows: rows, dragID: b, insertion: 1) == nil)
    #expect(SidebarDrop.resolve(rows: rows, dragID: b, insertion: 2) == nil)
}

@Test func unknownDragIDOrOutOfRangeInsertionIsNil() {
    let rows = [row(a), row(b)]
    #expect(SidebarDrop.resolve(rows: rows, dragID: UUID(), insertion: 0) == nil)
    #expect(SidebarDrop.resolve(rows: rows, dragID: a, insertion: 3) == nil)
    #expect(SidebarDrop.resolve(rows: rows, dragID: a, insertion: -1) == nil)
}

@Test func moveWithinSegmentAnchorsBeforeNext() {
    let rows = [row(a), row(b), row(c), row(d)]
    // a giù tra c e d.
    #expect(SidebarDrop.resolve(rows: rows, dragID: a, insertion: 3)
        == SidebarDrop.Resolution(pinned: nil, move: .before(d)))
    // d su tra a e b.
    #expect(SidebarDrop.resolve(rows: rows, dragID: d, insertion: 1)
        == SidebarDrop.Resolution(pinned: nil, move: .before(b)))
}

@Test func moveToEndAnchorsAfterLast() {
    let rows = [row(a), row(b), row(c)]
    #expect(SidebarDrop.resolve(rows: rows, dragID: a, insertion: 3)
        == SidebarDrop.Resolution(pinned: nil, move: .after(c)))
}

@Test func moveToTopAnchorsBeforeFirst() {
    let rows = [row(a), row(b), row(c)]
    #expect(SidebarDrop.resolve(rows: rows, dragID: c, insertion: 0)
        == SidebarDrop.Resolution(pinned: nil, move: .before(a)))
}

@Test func dropInsidePinnedBlockPins() {
    // a,b pinned; c,d no. c rilasciato tra a e b: si pinna lì.
    let rows = [row(a, pinned: true), row(b, pinned: true), row(c), row(d)]
    #expect(SidebarDrop.resolve(rows: rows, dragID: c, insertion: 1)
        == SidebarDrop.Resolution(pinned: true, move: .before(b)))
    // In testa al blocco: sopra una riga pinned si sta solo da pinned.
    #expect(SidebarDrop.resolve(rows: rows, dragID: c, insertion: 0)
        == SidebarDrop.Resolution(pinned: true, move: .before(a)))
}

@Test func dropBelowPinnedBlockUnpins() {
    let rows = [row(a, pinned: true), row(b, pinned: true), row(c), row(d)]
    // a rilasciato tra c e d: si spinna e si posa lì.
    #expect(SidebarDrop.resolve(rows: rows, dragID: a, insertion: 3)
        == SidebarDrop.Resolution(pinned: false, move: .before(d)))
}

@Test func boundarySlotKeepsPinState() {
    let rows = [row(a, pinned: true), row(b, pinned: true), row(c), row(d)]
    // b al bordo del blocco (slot 2 = proprio slot sotto: no-op); usa d al bordo: resta unpinned
    // e si posa in testa al resto.
    #expect(SidebarDrop.resolve(rows: rows, dragID: d, insertion: 2)
        == SidebarDrop.Resolution(pinned: nil, move: .before(c)))
    // a al bordo (sotto b, sopra c): resta pinned, in fondo al blocco (ancora after: il primo
    // del segmento successivo non è contiguo in canonico).
    #expect(SidebarDrop.resolve(rows: rows, dragID: a, insertion: 2)
        == SidebarDrop.Resolution(pinned: nil, move: .after(b)))
}

@Test func pinnedAloneCanUnpinByDraggingOut() {
    // Anche il blocco pinned da 1 elemento non è una zona morta: trascinarlo fuori lo spinna.
    let rows = [row(a, pinned: true), row(b), row(c)]
    #expect(SidebarDrop.resolve(rows: rows, dragID: a, insertion: 2)
        == SidebarDrop.Resolution(pinned: false, move: .before(c)))
}
