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

@Test @MainActor func needsInputSetsStateNotAttention() {
    let fixture = makeFixture()
    let applied = fixture.store.applyAgentState(
        paneId: fixture.hiddenTab.id.uuidString,
        state: .needsInput,
        at: Date(timeIntervalSince1970: 10)
    )
    #expect(applied)
    // needs_input e' uno stato: il badge lo mostra dallo stato, senza marker "unread".
    #expect(fixture.hiddenTab.agentState == .needsInput)
    #expect(!fixture.hiddenTab.attention)
    #expect(fixture.hiddenTab.lastEventAt == Date(timeIntervalSince1970: 10))
}

@Test @MainActor func completedOnHiddenTabRaisesAttention() {
    let fixture = makeFixture()
    let tabID = fixture.hiddenTab.id.uuidString
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .running,
        at: Date(timeIntervalSince1970: 1)
    )
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(timeIntervalSince1970: 2))
    #expect(fixture.hiddenTab.agentState == .idle)
    #expect(fixture.hiddenTab.attention) // completato mentre non guardavi
}

@Test @MainActor func completedOnVisibleTabStaysCalm() {
    let fixture = makeFixture()
    let tabID = fixture.visibleTab.id.uuidString
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .running,
        at: Date(timeIntervalSince1970: 1)
    )
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(timeIntervalSince1970: 2))
    #expect(fixture.visibleTab.agentState == .idle)
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

@Test @MainActor func emitsNeedsInputNotificationOnceOnEntry() {
    let fixture = makeFixture()
    var emitted: [AgentNotification] = []
    fixture.store.onNotifiableTransition = { emitted.append($0) }
    let tabID = fixture.hiddenTab.id.uuidString
    fixture.store.applyAgentState(paneId: tabID, state: .needsInput, at: Date())
    #expect(emitted.count == 1)
    #expect(emitted.first?.kind == .needsInput)
    #expect(emitted.first?.isVisible == false)
    #expect(emitted.first?.workspaceName == "B")
    // Un secondo evento needs_input non ri-notifica (è già in quello stato).
    fixture.store.applyAgentState(paneId: tabID, state: .needsInput, at: Date())
    #expect(emitted.count == 1)
}

@Test @MainActor func inactiveAppTreatsSelectedTabAsHidden() {
    // Relay in background: anche la tab in vista completa "non vista" -> marker acceso + notifica.
    let fixture = makeFixture()
    var emitted: [AgentNotification] = []
    fixture.store.onNotifiableTransition = { emitted.append($0) }
    let tabID = fixture.visibleTab.id.uuidString
    fixture.store.applyAgentState(paneId: tabID, state: .running, at: Date(), appActive: false)
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(), appActive: false)
    #expect(fixture.visibleTab.attention) // completato non visto, anche se selezionata
    #expect(emitted.map(\.kind) == [.completed])
}

@Test @MainActor func activeAppOnSelectedTabStaysCalm() {
    // Relay in primo piano sulla tab in vista: completare non accende marker né notifica.
    let fixture = makeFixture()
    var emitted: [AgentNotification] = []
    fixture.store.onNotifiableTransition = { emitted.append($0) }
    let tabID = fixture.visibleTab.id.uuidString
    fixture.store.applyAgentState(paneId: tabID, state: .running, at: Date(), appActive: true)
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(), appActive: true)
    #expect(!fixture.visibleTab.attention)
    #expect(emitted.isEmpty)
}

@Test @MainActor func emitsCompletedNotificationOnlyWhenHidden() {
    let fixture = makeFixture()
    var emitted: [AgentNotification] = []
    fixture.store.onNotifiableTransition = { emitted.append($0) }

    let hidden = fixture.hiddenTab.id.uuidString
    fixture.store.applyAgentState(paneId: hidden, state: .running, at: Date())
    fixture.store.applyAgentState(paneId: hidden, state: .idle, at: Date())
    #expect(emitted.map(\.kind) == [.completed]) // start non notifica, il completamento sì

    emitted.removeAll()
    let visible = fixture.visibleTab.id.uuidString
    fixture.store.applyAgentState(paneId: visible, state: .running, at: Date())
    fixture.store.applyAgentState(paneId: visible, state: .idle, at: Date())
    #expect(emitted.isEmpty) // sulla tab in vista, completare non notifica
}
