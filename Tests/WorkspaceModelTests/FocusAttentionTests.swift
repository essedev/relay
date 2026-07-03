import AgentProtocol
import Testing
@testable import WorkspaceModel

// `focusNextAttention` guida il jump (Cmd+J): porta in vista la prossima tab che aspetta input o
// ha completato del lavoro non visto, in ordine visivo (`orderedWorkspaces`) e ciclico.

@Test func jumpDoesNothingWhenNoAttention() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "A")
    store.createWorkspace(name: "B")
    store.selectWorkspace(a.id)

    #expect(store.focusNextAttention() == false)
    #expect(store.selectedWorkspaceID == a.id)
}

@Test func jumpSelectsTabNeedingAttention() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "A")
    let b = store.createWorkspace(name: "B")
    store.selectWorkspace(a.id) // A non ha attenzione
    b.tabs[0].agentState = .needsInput

    #expect(store.focusNextAttention())
    #expect(store.selectedWorkspaceID == b.id)
    #expect(b.selectedTabID == b.tabs[0].id)
}

@Test func jumpSkipsTheCurrentTabAndCycles() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "A")
    let b = store.createWorkspace(name: "B")
    a.tabs[0].attention = .unseen // completamento non visto
    b.tabs[0].agentState = .needsInput
    store.selectWorkspace(a.id) // parte dalla tab in attenzione A

    // Salta la corrente -> B.
    #expect(store.focusNextAttention())
    #expect(store.selectedWorkspaceID == b.id)
    // Ancora -> cicla e torna ad A.
    #expect(store.focusNextAttention())
    #expect(store.selectedWorkspaceID == a.id)
}

/// Due livelli: finché c'è attenzione fresca (needs_input/unseen) il jump ignora i sospesi;
/// esauriti i freschi, passa ai sospesi.
@Test func jumpPrefersFreshOverPending() {
    let store = WorkspaceStore()
    let current = store.createWorkspace(name: "current")
    let pending = store.createWorkspace(name: "pending")
    let fresh = store.createWorkspace(name: "fresh")
    pending.tabs[0].attention = .pending
    fresh.tabs[0].attention = .unseen
    store.selectWorkspace(current.id)

    // Col fresco presente, il jump lo preferisce al sospeso (anche se viene dopo).
    #expect(store.focusNextAttention())
    #expect(store.selectedWorkspaceID == fresh.id)

    // Fresco risolto: il jump ripiega sul sospeso.
    fresh.tabs[0].attention = .none
    #expect(store.focusNextAttention())
    #expect(store.selectedWorkspaceID == pending.id)
}

@Test func jumpReachesAnotherTabInSameWorkspace() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "A")
    let second = store.addTab(to: a) // selezionata alla creazione
    second.agentState = .needsInput
    store.selectTab(a.tabs[0].id, in: a) // torno alla prima, senza attenzione

    #expect(store.focusNextAttention())
    #expect(a.selectedTabID == second.id)
}
