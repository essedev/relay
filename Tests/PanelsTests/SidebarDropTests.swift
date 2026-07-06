import Foundation
@testable import Panels
import Testing

// La logica pura di drop della sidebar: regioni di pin, ancore per segmento, no-op. Copre i buchi
// che il vecchio clamp di segmento lasciava (segmenti da 1 elemento = drag morto).

private func row(
    _ id: UUID, pinned: Bool = false, attention: Bool = false
) -> SidebarDrop.Row {
    SidebarDrop.Row(id: id, pinned: pinned, attention: attention)
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

@Test func soloFloatingWorkspaceCanMoveDown() {
    // Il caso del bug: b flotta da solo (segmento 1). Col vecchio clamp ogni drop era un no-op;
    // ora si ancora ai vicini grezzi e fissa la sua casa canonica.
    let rows = [row(b, attention: true), row(a), row(c)]
    #expect(SidebarDrop.resolve(rows: rows, dragID: b, insertion: 3)
        == SidebarDrop.Resolution(pinned: nil, move: .after(c)))
    #expect(SidebarDrop.resolve(rows: rows, dragID: b, insertion: 2)
        == SidebarDrop.Resolution(pinned: nil, move: .before(c)))
}

@Test func restDroppedAboveFloatingLandsTopOfRest() {
    // c (resto) rilasciato sopra b che flotta: non può stare sopra visivamente, ma si posa in
    // testa al proprio segmento (l'ancora preferisce il compagno di segmento).
    let rows = [row(b, attention: true), row(a), row(c)]
    #expect(SidebarDrop.resolve(rows: rows, dragID: c, insertion: 0)
        == SidebarDrop.Resolution(pinned: nil, move: .before(a)))
}

@Test func floatingDroppedBetweenFloatingStaysExact() {
    let rows = [row(a, attention: true), row(b, attention: true), row(c)]
    #expect(SidebarDrop.resolve(rows: rows, dragID: b, insertion: 0)
        == SidebarDrop.Resolution(pinned: nil, move: .before(a)))
}

@Test func pinnedAloneCanUnpinByDraggingOut() {
    // Anche il blocco pinned da 1 elemento non è una zona morta: trascinarlo fuori lo spinna.
    let rows = [row(a, pinned: true), row(b), row(c)]
    #expect(SidebarDrop.resolve(rows: rows, dragID: a, insertion: 2)
        == SidebarDrop.Resolution(pinned: false, move: .before(c)))
}
