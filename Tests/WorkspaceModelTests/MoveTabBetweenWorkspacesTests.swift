import Foundation
import Testing
@testable import WorkspaceModel

// Spostare una tab in un altro workspace **esistente** (drag dalla strip alla sidebar).
// L'invariante che conta è che viaggi lo stesso oggetto `Tab`: la surface è legata al suo id,
// se ne creassimo una copia il pty morirebbe.

@Test func moveTabBetweenWorkspacesKeepsTheSameTabObject() {
    let store = WorkspaceStore()
    let src = store.createWorkspace(name: "src")
    let dst = store.createWorkspace(name: "dst")
    let mover = store.addTab(to: src)

    #expect(store.moveTab(mover.id, from: src, to: dst))

    #expect(src.tabs.contains { $0.id == mover.id } == false)
    #expect(dst.tabs.contains { $0 === mover })
    #expect(dst.layout.paneID(containing: mover.id) != nil)
}

@Test func movedTabBecomesVisibleInItsNewWorkspace() {
    let store = WorkspaceStore()
    let src = store.createWorkspace(name: "src")
    let dst = store.createWorkspace(name: "dst")
    let resident = dst.tabs[0]
    let mover = store.addTab(to: src)
    store.selectWorkspace(src.id)

    store.moveTab(mover.id, from: src, to: dst)

    #expect(dst.selectedTabID == mover.id)
    #expect(store.selectedWorkspaceID == dst.id)
    // Entra accanto alla tab selezionata della destinazione, non in fondo a caso.
    #expect(dst.tabs.map(\.id).contains(resident.id))
}

@Test func movingIntoAnArchivedWorkspaceRevealsIt() {
    let store = WorkspaceStore()
    let src = store.createWorkspace(name: "src")
    let dst = store.createWorkspace(name: "dst")
    let mover = store.addTab(to: src)
    store.setArchived(dst.id, true)

    store.moveTab(mover.id, from: src, to: dst)

    #expect(dst.archived == false)
    #expect(store.selectedWorkspaceID == dst.id)
}

@Test func movingTheLastTabClosesTheSourceWorkspace() {
    let store = WorkspaceStore()
    let src = store.createWorkspace(name: "src")
    let dst = store.createWorkspace(name: "dst")
    let onlyTab = src.tabs[0]

    // A differenza di "Move to New Workspace" qui non è un rename mascherato: la tab va davvero
    // altrove, quindi l'origine svuotata si chiude (cascade, come closeTab).
    #expect(store.moveTab(onlyTab.id, from: src, to: dst))

    #expect(store.workspaces.map(\.id) == [dst.id])
    #expect(dst.tabs.contains { $0.id == onlyTab.id })
}

@Test func moveTabBetweenWorkspacesIsNoOpForTheSameWorkspaceOrAnUnknownTab() {
    let store = WorkspaceStore()
    let src = store.createWorkspace(name: "src")
    let dst = store.createWorkspace(name: "dst")
    let tab = src.tabs[0]

    #expect(store.moveTab(tab.id, from: src, to: src) == false)
    #expect(store.moveTab(UUID(), from: src, to: dst) == false)
    #expect(src.tabs.map(\.id) == [tab.id])
    #expect(dst.tabs.count == 1)
}

@Test func aMovedTabKeepsItsAgentStateAndAttention() throws {
    let store = WorkspaceStore()
    let src = store.createWorkspace(name: "src")
    let dst = store.createWorkspace(name: "dst")
    let mover = store.addTab(to: src)
    mover.attention = .unseen
    mover.title = "claude"

    store.moveTab(mover.id, from: src, to: dst)

    let moved = try #require(dst.tabs.first { $0.id == mover.id })
    #expect(moved.attention == .unseen)
    #expect(moved.title == "claude")
}
