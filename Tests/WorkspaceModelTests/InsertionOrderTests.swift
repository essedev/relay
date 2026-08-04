import Foundation
import Testing
@testable import WorkspaceModel

// Dove nasce una cosa nuova: una tab accanto a quella selezionata nel suo pane, un workspace
// accanto (e dentro il gruppo) di quello selezionato. Non in fondo alla lista.

@Test func newTabLandsAfterTheSelectedTab() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "api")
    let first = ws.tabs[0]
    let second = store.addTab(to: ws)
    let third = store.addTab(to: ws)
    #expect(ws.orderedTabs.map(\.id) == [first.id, second.id, third.id])

    // Torno sulla prima: la nuova nasce subito dopo di lei, non in coda.
    store.selectTab(first.id, in: ws)
    let inserted = store.addTab(to: ws)

    #expect(ws.orderedTabs.map(\.id) == [first.id, inserted.id, second.id, third.id])
    #expect(ws.selectedTabID == inserted.id)
}

@Test func newTabLandsInTheFocusedPaneAfterItsSelection() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "api")
    let left = ws.tabs[0]
    let leftSecond = store.addTab(to: ws)
    // Split: il pane nuovo nasce con la sua tab e prende il focus.
    let right = try #require(store.splitPane(axis: .horizontal, in: ws))

    let inserted = store.addTab(to: ws)

    // Finisce nel pane focused, dopo la sua selezione: l'altra strip resta intatta.
    let panes = ws.layout.panes
    #expect(panes.count == 2)
    #expect(panes.first { $0.id != ws.focusedPaneID }?.tabIDs == [left.id, leftSecond.id])
    #expect(panes.first { $0.id == ws.focusedPaneID }?.tabIDs == [right.id, inserted.id])
}

@Test func newWorkspaceLandsAfterTheSelectedOne() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")
    // Creazioni in sequenza: ognuna dopo la precedente, quindi l'ordine di creazione si conserva.
    #expect(store.workspaces.map(\.id) == [a.id, b.id, c.id])

    store.selectWorkspace(a.id)
    let inserted = store.createWorkspace(name: "new")

    #expect(store.workspaces.map(\.id) == [a.id, inserted.id, b.id, c.id])
    #expect(store.selectedWorkspaceID == inserted.id)
}

@Test func newWorkspaceJoinsTheGroupOfTheSelectedOne() throws {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let outside = store.createWorkspace(name: "outside")
    let group = try #require(store.createGroup(name: "Work", with: [a.id, b.id]))

    store.selectWorkspace(a.id)
    let inserted = store.createWorkspace(name: "new")

    // Creare dentro una card crea dentro quella card, subito sotto la riga da cui sei partito.
    #expect(inserted.groupID == group.id)
    #expect(store.members(of: group.id).map(\.id) == [a.id, inserted.id, b.id])
    #expect(store.workspaces.map(\.id) == [a.id, inserted.id, b.id, outside.id])
}

@Test func newWorkspaceOpensTheCollapsedCardItWasBornIn() throws {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let group = try #require(store.createGroup(name: "Work", with: [a.id]))
    store.toggleGroupCollapsed(group.id)
    store.selectWorkspace(a.id)

    let inserted = store.createWorkspace(name: "new")

    // Selezionare una riga dentro una card chiusa la aprirebbe (`reveal`): idem quando la riga
    // nasce lì, o il selezionato sarebbe invisibile in sidebar.
    #expect(inserted.groupID == group.id)
    #expect(store.group(group.id)?.collapsed == false)
    #expect(store.navigableWorkspaces.map(\.id) == [a.id, inserted.id])
}

@Test func newWorkspaceAfterAPinnedOneIsNotPinned() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    store.togglePin(a.id)
    store.selectWorkspace(a.id)

    let inserted = store.createWorkspace(name: "new")

    // Il nuovo non eredita il pin: nell'ordine visivo apre il segmento non pinned, la riga più
    // vicina possibile a quella da cui è nato.
    #expect(inserted.pinned == false)
    #expect(store.orderedWorkspaces.map(\.id) == [a.id, inserted.id, b.id])
}

@Test func newWorkspaceFallsBackToTheEndWhenTheSelectedIsArchived() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    store.setArchived(a.id, true)
    store.keyWindow?.selectedWorkspaceID = a.id // stato limite: un archiviato come selezione

    let inserted = store.createWorkspace(name: "new")

    // Un archiviato sta fuori da `orderedWorkspaces`: ancorarcisi darebbe una posizione che nella
    // lista non corrisponde a niente, quindi si torna al fondo.
    #expect(inserted.groupID == nil)
    #expect(store.workspaces.map(\.id) == [a.id, b.id, inserted.id])
}

@Test func newWorkspaceAnchorsToTheSelectionOfItsOwnWindow() throws {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let second = try #require(store.moveWorkspaceToNewWindow(b.id))
    store.activateWindow(RelayWindow.mainID)
    store.selectWorkspace(a.id)

    let inserted = store.createWorkspace(name: "new", in: second.id, select: false)

    // L'ancora è la selezione della finestra di destinazione (b), non quella della key (a).
    #expect(store.workspaces.map(\.id) == [a.id, b.id, inserted.id])
    #expect(inserted.windowID == second.id)
    #expect(store.selectedWorkspaceID == a.id)
}

@Test func movedTabLandsInANewWorkspaceNextToItsOrigin() throws {
    let store = WorkspaceStore()
    let src = store.createWorkspace(name: "src")
    let other = store.createWorkspace(name: "other")
    let group = try #require(store.createGroup(name: "Work", with: [src.id]))
    let mover = store.addTab(to: src)

    let dst = try #require(store.moveTabToNewWorkspace(mover.id, from: src, name: "Workspace 3"))

    // Stessa regola di `createWorkspace`: accanto all'origine e nel suo gruppo.
    #expect(dst.groupID == group.id)
    #expect(store.workspaces.map(\.id) == [src.id, dst.id, other.id])
}
