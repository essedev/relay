import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

// Gruppi della sidebar: appartenenza, ciclo di vita (un gruppo senza membri non esiste),
// proiezione dell'ordine e bump "in cima al proprio contenitore".

@Test func createGroupCompactsMembersAndClearsTheirPin() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")
    store.togglePin(c.id)

    let group = store.createGroup(name: "Work", with: [a.id, c.id])
    #expect(group != nil)
    #expect(c.pinned == false) // dentro una card pinna la card, non la riga
    // I membri si compattano attorno al primo: la card nasce dove stava la riga di partenza.
    #expect(store.workspaces.map(\.id) == [a.id, c.id, b.id])
    #expect(store.orderedWorkspaces.map(\.id) == [a.id, c.id, b.id])
}

@Test func groupDiesWithItsLastMember() throws {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    store.createWorkspace(name: "b")
    let group = try #require(store.createGroup(name: "Solo", with: [a.id]))

    store.removeFromGroup(a.id)
    #expect(store.groups.isEmpty)
    #expect(store.group(group.id) == nil)
}

@Test func closingTheLastMemberAlsoRemovesTheGroup() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    store.createWorkspace(name: "b")
    store.createGroup(name: "Solo", with: [a.id])

    store.closeWorkspace(a.id)
    #expect(store.groups.isEmpty)
}

@Test func archivingAMemberTakesItOutOfTheCard() throws {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    store.createWorkspace(name: "c")
    let group = try #require(store.createGroup(name: "Work", with: [a.id, b.id]))

    store.setArchived(a.id, true)
    #expect(a.groupID == nil)
    #expect(store.members(of: group.id).map(\.id) == [b.id])
}

@Test func pinnedGroupLeadsTheSidebar() throws {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")
    let group = try #require(store.createGroup(name: "Work", with: [b.id, c.id]))

    #expect(store.orderedWorkspaces.map(\.id) == [a.id, b.id, c.id])
    store.setGroupPinned(group.id, true)
    #expect(store.orderedWorkspaces.map(\.id) == [b.id, c.id, a.id])
    #expect(store.sidebarItems.first?.id == group.id)
}

@Test func collapsedMembersLeaveTheNumericNavigation() throws {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")
    let group = try #require(store.createGroup(name: "Work", with: [b.id, c.id]))

    store.toggleGroupCollapsed(group.id)
    // Restano nell'ordine logico (Cmd+J, eredi di selezione) ma non nella numerazione: una
    // scorciatoia che seleziona una riga invisibile non è una scorciatoia.
    #expect(store.orderedWorkspaces.map(\.id) == [a.id, b.id, c.id])
    #expect(store.navigableWorkspaces.map(\.id) == [a.id])
}

@Test func revealOpensTheCardOfItsWorkspace() throws {
    let store = WorkspaceStore()
    store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let group = try #require(store.createGroup(name: "Work", with: [b.id]))
    store.toggleGroupCollapsed(group.id)

    store.reveal(workspaceID: b.id, tabID: b.tabs[0].id)
    #expect(store.group(group.id)?.collapsed == false)
    #expect(store.selectedWorkspaceID == b.id)
}

@Test func bumpStaysInsideTheCard() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")
    store.createGroup(name: "Work", with: [b.id, c.id])

    store.bumpWorkspaceToTop(c.id)
    // c sale in cima **alla sua card**, la card non si muove.
    #expect(store.orderedWorkspaces.map(\.id) == [a.id, c.id, b.id])
}

@Test func bumpOfAFreeWorkspaceLandsAboveTheCard() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")
    store.createGroup(name: "Work", with: [a.id, b.id])

    store.bumpWorkspaceToTop(c.id)
    #expect(store.orderedWorkspaces.map(\.id) == [c.id, a.id, b.id])
    #expect(store.sidebarItems.first?.id == c.id)
}

@Test func movingToAnotherWindowLeavesTheGroup() throws {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let group = try #require(store.createGroup(name: "Work", with: [a.id, b.id]))

    store.moveWorkspaceToNewWindow(a.id)
    #expect(a.groupID == nil)
    #expect(store.members(of: group.id).map(\.id) == [b.id])
}

@Test func groupsSurviveASnapshotRoundTrip() throws {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let group = try #require(store.createGroup(name: "Work", with: [a.id, b.id]))
    store.setGroupColor(group.id, colorIndex: 5)
    store.toggleGroupCollapsed(group.id)

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())
    #expect(restored.groups.map(\.name) == ["Work"])
    #expect(restored.group(group.id)?.colorIndex == 5)
    #expect(restored.group(group.id)?.collapsed == true)
    #expect(restored.members(of: group.id).map(\.name) == ["a", "b"])
}

@Test func orphanGroupIDDegradesToAFreeRow() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    a.groupID = UUID() // gruppo inesistente (file toccato a mano)

    #expect(store.sidebarItems.count == 1)
    #expect(store.sidebarItems.first?.id == a.id)
}

@Test func aGroupNeedsAtLeastOneRealWorkspace() {
    let store = WorkspaceStore()
    store.createWorkspace(name: "a")
    #expect(store.createGroup(name: "Empty", with: []) == nil)
    #expect(store.groups.isEmpty)
}
