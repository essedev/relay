import AgentProtocol
import Testing
@testable import WorkspaceModel

@Test func idleToIdleIsNoiseFree() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .idle,
        isVisible: false,
        currentAttention: false
    )
    #expect(result == AgentStateReducer.Result(state: .idle, attention: false))
}

@Test func completedWhileHiddenRaisesAttention() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .idle,
        isVisible: false,
        currentAttention: false
    )
    #expect(result == AgentStateReducer.Result(state: .idle, attention: true))
}

@Test func completedWhileVisibleStaysCalm() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .idle,
        isVisible: true,
        currentAttention: false
    )
    #expect(result == AgentStateReducer.Result(state: .idle, attention: false))
}

/// needs_input è uno stato, non un marker: non tocca `attention` (il badge lo mostra dallo stato,
/// e resta finché rispondi a Claude - non si spegne alla visita).
@Test func needsInputDoesNotUseAttentionWhenHidden() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .needsInput,
        isVisible: false,
        currentAttention: false
    )
    #expect(result == AgentStateReducer.Result(state: .needsInput, attention: false))
}

@Test func needsInputDoesNotUseAttentionWhenVisible() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .needsInput,
        isVisible: true,
        currentAttention: false
    )
    #expect(result == AgentStateReducer.Result(state: .needsInput, attention: false))
}

@Test func errorDoesNotUseAttention() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .error,
        isVisible: false,
        currentAttention: false
    )
    #expect(result == AgentStateReducer.Result(state: .error, attention: false))
}

/// Un evento running mentre sei altrove non cancella un "completato non visto" gia' presente
/// (comunque il badge running ha precedenza finche' lo stato e' running).
@Test func runningPreservesExistingCompletedMarker() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .running,
        isVisible: false,
        currentAttention: true
    )
    #expect(result == AgentStateReducer.Result(state: .running, attention: true))
}

@Test func visitingClearsCompletedMarker() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .running,
        isVisible: true,
        currentAttention: true
    )
    #expect(result == AgentStateReducer.Result(state: .running, attention: false))
}
