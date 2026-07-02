import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

/// `applyAgentState` è il path che il coordinatore esegue per ogni evento: locate della tab via
/// paneId, calcolo visibilità, reducer. Qui lo testiamo senza socket né app.
private struct Fixture {
    let store: WorkspaceStore
    let visibleTab: Tab
    let hiddenTab: Tab
}

@MainActor
private func makeFixture() -> Fixture {
    let store = WorkspaceStore()
    let visible = store.createWorkspace(name: "A")
    let hidden = store.createWorkspace(name: "B")
    // L'ultima creata resta selezionata: rendo esplicito che "A" è la visibile.
    store.selectWorkspace(visible.id)
    return Fixture(store: store, visibleTab: visible.tabs[0], hiddenTab: hidden.tabs[0])
}

@Test @MainActor func applyToHiddenTabRaisesAttention() {
    let fixture = makeFixture()
    let applied = fixture.store.applyAgentState(
        paneId: fixture.hiddenTab.id.uuidString,
        state: .needsInput,
        at: Date(timeIntervalSince1970: 10)
    )
    #expect(applied)
    #expect(fixture.hiddenTab.agentState == .needsInput)
    #expect(fixture.hiddenTab.attention)
    #expect(fixture.hiddenTab.lastEventAt == Date(timeIntervalSince1970: 10))
}

@Test @MainActor func applyToVisibleTabStaysCalm() {
    let fixture = makeFixture()
    let applied = fixture.store.applyAgentState(
        paneId: fixture.visibleTab.id.uuidString,
        state: .needsInput,
        at: Date(timeIntervalSince1970: 10)
    )
    #expect(applied)
    #expect(fixture.visibleTab.agentState == .needsInput)
    #expect(!fixture.visibleTab.attention)
}

@Test @MainActor func applyUnknownTabIsNoOp() {
    let fixture = makeFixture()
    #expect(!fixture.store.applyAgentState(paneId: UUID().uuidString, state: .running, at: Date()))
}

@Test @MainActor func applyInvalidPaneIdIsNoOp() {
    let fixture = makeFixture()
    #expect(!fixture.store.applyAgentState(paneId: "not-a-uuid", state: .running, at: Date()))
}
