import Foundation
@testable import Panels
import Testing

// La logica pura della sidebar: piano di righe e slot (`SidebarLayout`) e risoluzione del drop
// (`SidebarDrop`). Copre i tre contenitori (lista con/senza pin, card di un gruppo, archivio) e i
// due confini che a occhio sono lo stesso pixel: "in fondo alla card" contro "sotto la card".

private let a = UUID()
private let b = UUID()
private let c = UUID()
private let d = UUID()
private let g = UUID()

private func free(_ id: UUID, pinned: Bool = false) -> SidebarLayout.Item {
    SidebarLayout.Item(id: id, kind: .workspace, pinned: pinned)
}

private func group(
    _ id: UUID, _ members: [UUID], collapsed: Bool = false, pinned: Bool = false
) -> SidebarLayout.Item {
    SidebarLayout.Item(id: id, kind: .group(members: members, collapsed: collapsed), pinned: pinned)
}

private func plan(
    _ items: [SidebarLayout.Item], archived: [UUID] = [], archiveExpanded: Bool = true
) -> SidebarLayout.Plan {
    SidebarLayout.plan(items: items, archived: archived, archiveExpanded: archiveExpanded)
}

// MARK: - Piano

@Test func planUnrollsGroupsWithHeaderAndTail() {
    let p = plan([free(a), group(g, [b, c])])
    #expect(p.rows == [
        .workspace(a),
        .groupHeader(g),
        .member(b, group: g),
        .member(c, group: g),
        .groupTail(g),
        .archiveHeader,
    ])
    // Lo slot dopo l'ultimo membro è dentro la card, quello dopo la coda è nella lista: è la
    // distinzione che nessuna euristica sui vicini potrebbe fare.
    #expect(p.slots[4] == .group(g))
    #expect(p.slots[5] == .root(pinned: false))
}

@Test func collapsedGroupHasNoInnerSlots() {
    let p = plan([group(g, [b, c], collapsed: true), free(a)])
    #expect(p.rows == [.groupHeader(g), .workspace(a), .archiveHeader])
    #expect(p.slots[1] == .root(pinned: false)) // sotto una card chiusa non ci si rilascia dentro
}

@Test func archiveHeaderIsAlwaysPresentAsDropZone() {
    let p = plan([free(a)], archived: [], archiveExpanded: false)
    #expect(p.rows.last == .archiveHeader)
    #expect(p.slots.last == .archive)
}

// MARK: - Drop nella lista

@Test func dropInOwnSlotIsNoOp() {
    let p = plan([free(a), free(b), free(c)])
    #expect(SidebarDrop.resolve(
        plan: p, items: [free(a), free(b), free(c)], dragged: .workspace(b), insertion: 1
    ) == nil)
    #expect(SidebarDrop.resolve(
        plan: p, items: [free(a), free(b), free(c)], dragged: .workspace(b), insertion: 2
    ) == nil)
}

@Test func moveWithinListAnchorsBeforeNext() {
    let items = [free(a), free(b), free(c)]
    let p = plan(items)
    #expect(SidebarDrop.resolve(plan: p, items: items, dragged: .workspace(a), insertion: 2)
        == SidebarDrop.Resolution(container: .root(pinned: false), move: .before(c)))
}

@Test func crossingThePinnedBlockPins() {
    let items = [free(a, pinned: true), free(b), free(c)]
    let p = plan(items)
    // b sale sopra il pinned: entra nel blocco.
    let up = SidebarDrop.resolve(plan: p, items: items, dragged: .workspace(b), insertion: 0)
    #expect(up == SidebarDrop.Resolution(container: .root(pinned: true), move: .before(a)))
    // a scende sotto i liberi: esce dal blocco.
    let down = SidebarDrop.resolve(plan: p, items: items, dragged: .workspace(a), insertion: 3)
    #expect(down == SidebarDrop.Resolution(container: .root(pinned: false), move: .after(c)))
}

// MARK: - Drop dentro e fuori una card

@Test func dropBetweenMembersEntersTheGroup() {
    let items = [free(a), group(g, [b, c])]
    let p = plan(items)
    // Slot fra b e c (indice 3): dentro la card, ancorato al membro successivo.
    #expect(SidebarDrop.resolve(plan: p, items: items, dragged: .workspace(a), insertion: 3)
        == SidebarDrop.Resolution(container: .group(g), move: .before(c)))
}

@Test func dropOnTailAppendsToGroupAndBelowTailLeavesIt() {
    let items = [free(a), group(g, [b, c])]
    let p = plan(items)
    // Slot 4 = dopo l'ultimo membro, dentro la card.
    #expect(SidebarDrop.resolve(plan: p, items: items, dragged: .workspace(a), insertion: 4)
        == SidebarDrop.Resolution(container: .group(g), move: .after(c)))
    // Slot 5 = dopo la coda: fuori dalla card, subito sotto di lei nella lista.
    #expect(SidebarDrop.resolve(plan: p, items: items, dragged: .workspace(a), insertion: 5)
        == SidebarDrop.Resolution(container: .root(pinned: false), move: .after(c)))
}

@Test func memberDraggedOutOfTheCardLandsInTheList() {
    let items = [group(g, [b, c]), free(a)]
    let p = plan(items)
    // Piano: header, b, c, coda, a, archiveHeader. Slot 4 = fra la coda e a.
    #expect(SidebarDrop.resolve(plan: p, items: items, dragged: .workspace(b), insertion: 4)
        == SidebarDrop.Resolution(container: .root(pinned: false), move: .before(a)))
}

@Test func dropAboveAGroupAnchorsToItsFirstMember() {
    let items = [group(g, [b, c]), free(a)]
    let p = plan(items)
    #expect(SidebarDrop.resolve(plan: p, items: items, dragged: .workspace(a), insertion: 0)
        == SidebarDrop.Resolution(container: .root(pinned: false), move: .before(b)))
}

// MARK: - Archivio

@Test func dropUnderTheArchiveHeaderArchives() {
    let items = [free(a), free(b)]
    let p = plan(items, archived: [d])
    // Piano: a, b, archiveHeader, d. Slot 3 = subito sotto l'header.
    #expect(SidebarDrop.resolve(plan: p, items: items, dragged: .workspace(a), insertion: 3)
        == SidebarDrop.Resolution(container: .archive, move: .before(d)))
}

@Test func archivedDraggedBackIntoTheListIsRestored() {
    let items = [free(a), free(b)]
    let p = plan(items, archived: [d])
    #expect(SidebarDrop.resolve(plan: p, items: items, dragged: .workspace(d), insertion: 1)
        == SidebarDrop.Resolution(container: .root(pinned: false), move: .before(b)))
}

@Test func archiveWithNoRowsStillAcceptsADrop() {
    let items = [free(a), free(b)]
    let p = plan(items, archived: [], archiveExpanded: true)
    let drop = SidebarDrop.resolve(plan: p, items: items, dragged: .workspace(a), insertion: 3)
    // Nessun compagno di contenitore: resta il solo cambio di contenitore, senza ancora utile.
    #expect(drop?.container == .archive)
}

// MARK: - Drag di una card intera

@Test func groupSnapsToTheNearestListSlot() {
    let items = [group(g, [b, c]), free(a), free(d)]
    let p = plan(items)
    // Piano: header, b, c, coda, a, d, archiveHeader. Gli slot 1..3 sono dentro la card: una card
    // non si annida, quindi lo slot viene riportato al primo di primo livello.
    #expect(SidebarDrop.normalized(insertion: 2, plan: p, dragged: .group(g)) == 0)
    #expect(SidebarDrop.normalized(insertion: 5, plan: p, dragged: .group(g)) == 5)
}

@Test func groupMovesAsABlockAndCanBePinned() {
    let items = [free(a, pinned: true), free(d), group(g, [b, c])]
    let p = plan(items)
    // Piano: a, d, header, b, c, coda, archiveHeader. Slot 0 = dentro il blocco pinned.
    #expect(SidebarDrop.resolve(plan: p, items: items, dragged: .group(g), insertion: 0)
        == SidebarDrop.Resolution(container: .root(pinned: true), move: .before(a)))
}

@Test func dropOnOwnRowsIsNoOpForGroups() {
    let items = [free(a), group(g, [b, c])]
    let p = plan(items)
    // Piano: a, header, b, c, coda, archiveHeader. Gli slot 1..5 appartengono alla card.
    for slot in 1 ... 5 {
        #expect(SidebarDrop.resolve(
            plan: p, items: items, dragged: .group(g), insertion: slot
        ) == nil)
    }
}
