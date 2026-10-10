import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

// Chiudere un progetto è il gesto normale per metterlo via, quindi non deve far perdere niente:
// gruppo, tab e sessioni da riprendere restano, e riaprirlo lo rimette dov'era. Questi test
// difendono le due cose che lo rendono sicuro: il binding sopravvive all'agente che muore, e la
// finestra non resta mai a mostrare un progetto chiuso.

@MainActor
private func makeProject(
    _ store: WorkspaceStore, name: String, session: String? = nil
) -> Workspace {
    let workspace = store.createWorkspace(name: name)
    if let session {
        store.applyAgentState(
            paneId: workspace.tabs[0].id.uuidString,
            agent: "claude",
            sessionId: session,
            state: .idle,
            at: Date(timeIntervalSince1970: 10)
        )
    }
    return workspace
}

@Test @MainActor func closingReturnsEveryTabSoTheirSurfacesCanBeReleased() {
    let store = WorkspaceStore()
    let a = makeProject(store, name: "a")
    let b = makeProject(store, name: "b", session: "s-b")
    store.addTab(to: b)

    let released = store.setClosed(b.id, true)

    #expect(Set(released) == Set(b.tabs.map(\.id)))
    #expect(store.setClosed(b.id, true).isEmpty) // già chiuso: niente da buttare
    #expect(store.orderedWorkspaces.map(\.id) == [a.id])
}

@Test @MainActor func closingKeepsTheResumeBindingThroughTheDyingSessionEnd() {
    let store = WorkspaceStore()
    _ = makeProject(store, name: "a")
    let b = makeProject(store, name: "b", session: "s-b")
    let tab = b.tabs[0]

    store.setClosed(b.id, true)
    // L'agente ucciso dal teardown manda il suo SessionEnd dopo la chiusura.
    store.applyAgentState(
        paneId: tab.id.uuidString,
        agent: "claude",
        sessionId: "s-b",
        state: .unknown,
        at: Date(timeIntervalSince1970: 20)
    )

    #expect(tab.deactivated)
    #expect(tab.resume?.sessionId == "s-b")
}

@Test @MainActor func closingClearsAttentionAndThePin() {
    let store = WorkspaceStore()
    let a = makeProject(store, name: "a")
    let b = makeProject(store, name: "b")
    store.selectWorkspace(a.id)
    store.togglePin(b.id)
    let tab = b.tabs[0]
    store.applyAgentState(
        paneId: tab.id.uuidString, agent: "claude", sessionId: "s", state: .running,
        at: Date(timeIntervalSince1970: 10)
    )
    store.applyAgentState(
        paneId: tab.id.uuidString, agent: "claude", sessionId: "s", state: .idle,
        at: Date(timeIntervalSince1970: 11)
    )
    #expect(tab.attention == .unseen)

    store.setClosed(b.id, true)

    #expect(tab.attention == .none) // l'hai messo via tu: non ti sta aspettando
    #expect(!b.pinned)
}

@Test @MainActor func openingAClosedProjectSelectsItAndOpensItsCard() throws {
    let store = WorkspaceStore()
    let a = makeProject(store, name: "a")
    let b = makeProject(store, name: "b")
    let group = try #require(store.createGroup(name: "Work", with: [b.id]))
    store.setClosed(b.id, true)
    store.toggleGroupCollapsed(group.id)
    store.selectWorkspace(a.id)

    store.openProject(b.id)

    #expect(!b.closed)
    #expect(store.selectedWorkspaceID == b.id)
    #expect(store.group(group.id)?.collapsed == false)
    #expect(store.keyWindow?.page == .workspace)
}

@Test @MainActor func aPageCoversTheTerminalsSoTheTabIsNotOnScreen() {
    let store = WorkspaceStore()
    let a = makeProject(store, name: "a")
    let tab = a.tabs[0]
    store.keyWindow?.page = .home

    store.applyAgentState(
        paneId: tab.id.uuidString, agent: "claude", sessionId: "s", state: .running,
        at: Date(timeIntervalSince1970: 10)
    )
    store.applyAgentState(
        paneId: tab.id.uuidString, agent: "claude", sessionId: "s", state: .idle,
        at: Date(timeIntervalSince1970: 11)
    )

    // Selezionata, ma sotto la Home: il completamento resta da vedere.
    #expect(tab.attention == .unseen)
}

@Test @MainActor func selectingAProjectLeavesThePage() {
    let store = WorkspaceStore()
    let a = makeProject(store, name: "a")
    store.keyWindow?.page = .projects

    store.selectWorkspace(a.id)

    #expect(store.keyWindow?.page == .workspace)
}

@Test @MainActor func aClosedProjectKeepsItsGroupAcrossARestart() throws {
    let store = WorkspaceStore()
    _ = makeProject(store, name: "a")
    let b = makeProject(store, name: "b")
    let group = try #require(store.createGroup(name: "Work", with: [b.id]))
    store.setClosed(b.id, true)

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())

    let back = try #require(restored.workspaces.first { $0.id == b.id })
    #expect(back.closed)
    #expect(back.groupID == group.id)
    #expect(restored.groups.map(\.id) == [group.id])
}

@Test @MainActor func aWindowWithOnlyClosedProjectsRestoresOnHome() {
    let store = WorkspaceStore()
    let a = makeProject(store, name: "a")
    store.setClosed(a.id, true)

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())

    #expect(restored.selectedWorkspaceID == nil)
    #expect(restored.keyWindow?.page == .home)
}

@Test func theClosedFlagKeepsTheArchivedKeyOnDisk() throws {
    // La chiave resta quella di prima: un layout salvato da una versione precedente si legge
    // senza migrazione, e una versione precedente continua a leggere quello nuovo.
    let snapshot = WorkspaceSnapshot(
        id: UUID(), name: "p", rootPath: nil, pinned: false, closed: true,
        selectedTabID: nil, tabs: []
    )
    let data = try JSONEncoder().encode(snapshot)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["archived"] as? Bool == true)
    #expect(object["closed"] == nil)
    #expect(try JSONDecoder().decode(WorkspaceSnapshot.self, from: data).closed)
}
