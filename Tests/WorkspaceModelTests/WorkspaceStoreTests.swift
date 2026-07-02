import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

@Test func createWorkspaceSelectsItWithOneTab() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "api")

    #expect(store.workspaces.count == 1)
    #expect(store.selectedWorkspaceID == ws.id)
    #expect(ws.tabs.count == 1)
    #expect(ws.selectedTabID == ws.tabs.first?.id)
}

@Test func addTabSelectsNewTab() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "api")
    let tab = store.addTab(to: ws)

    #expect(ws.tabs.count == 2)
    #expect(ws.selectedTabID == tab.id)
}

@Test func addTabInheritsCurrentDirectoryFromSelectedTab() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "api")
    ws.tabs[0].currentDirectory = "/Users/doppia/dev/relay"

    let tab = store.addTab(to: ws)
    #expect(tab.currentDirectory == "/Users/doppia/dev/relay")

    // Senza cwd nota, la nuova tab non ne inventa una (fallback al rootPath a runtime).
    let bare = store.createWorkspace(name: "other")
    let bareTab = store.addTab(to: bare)
    #expect(bareTab.currentDirectory == nil)
}

@Test func closeSelectedTabSelectsNeighbor() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "api")
    let first = ws.tabs[0]
    let second = store.addTab(to: ws)
    store.selectTab(second.id, in: ws)

    let removed = store.closeTab(second.id, in: ws)

    #expect(removed == second.id)
    #expect(ws.tabs.count == 1)
    #expect(ws.selectedTabID == first.id)
}

@Test func closingLastTabClosesWorkspace() {
    let store = WorkspaceStore()
    let first = store.createWorkspace(name: "a")
    let second = store.createWorkspace(name: "b") // una sola tab
    let onlyTab = second.tabs[0]

    let removed = store.closeTab(onlyTab.id, in: second)

    #expect(removed == onlyTab.id)
    #expect(store.workspaces.map(\.id) == [first.id]) // il workspace vuoto è sparito
    #expect(store.selectedWorkspaceID == first.id)
}

@Test func moveWorkspaceOntoTargetTakesItsPosition() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")

    // c sopra a: c prende la posizione 0, a e b scorrono.
    store.moveWorkspace(c.id, onto: a.id)
    #expect(store.workspaces.map(\.id) == [c.id, a.id, b.id])

    // id inesistente o uguale: no-op.
    store.moveWorkspace(a.id, onto: a.id)
    #expect(store.workspaces.map(\.id) == [c.id, a.id, b.id])
}

@Test func closeWorkspaceReturnsTabIDsAndSelectsNeighbor() {
    let store = WorkspaceStore()
    let first = store.createWorkspace(name: "a")
    let second = store.createWorkspace(name: "b")
    let extraTab = store.addTab(to: second)

    let removed = store.closeWorkspace(second.id)

    #expect(Set(removed).contains(extraTab.id))
    #expect(removed.count == 2)
    #expect(store.workspaces.count == 1)
    #expect(store.selectedWorkspaceID == first.id)
}

@Test func togglePinPartitionsWorkspaces() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    _ = store.createWorkspace(name: "b")

    store.togglePin(a.id)

    #expect(store.pinnedWorkspaces.map(\.id) == [a.id])
    #expect(store.otherWorkspaces.count == 1)
}

@Test func moveWorkspacesReorders() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")

    store.moveWorkspaces(fromOffsets: IndexSet(integer: 1), toOffset: 0)

    #expect(store.workspaces.map(\.id) == [b.id, a.id])
}

@Test func renameWorkspaceIgnoresEmpty() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "api")

    store.renameWorkspace(ws.id, to: "  backend  ")
    #expect(ws.name == "backend") // trim

    store.renameWorkspace(ws.id, to: "   ")
    #expect(ws.name == "backend") // vuoto ignorato
}

@Test func orderedWorkspacesFloatsAttentionUnderPinned() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")

    // c pinnato; b chiede input -> ordine atteso: [c (pinned), b (attenzione), a (calmo)].
    store.togglePin(c.id)
    b.tabs[0].agentState = .needsInput

    #expect(store.orderedWorkspaces.map(\.id) == [c.id, b.id, a.id])

    // "completato non visto" (attention) galleggia come needs_input.
    b.tabs[0].agentState = .idle
    a.tabs[0].attention = true
    #expect(store.orderedWorkspaces.map(\.id) == [c.id, a.id, b.id])
}

@Test func renameTabSetsCustomTitle() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "a")
    let tab = ws.tabs[0]

    store.renameTab(tab.id, in: ws, to: "server")

    #expect(tab.title == "server")
    #expect(tab.hasCustomTitle)
}
