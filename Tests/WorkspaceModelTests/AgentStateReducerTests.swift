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

@Test func needsInputWhileHiddenRaisesAttention() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .needsInput,
        isVisible: false,
        currentAttention: false
    )
    #expect(result == AgentStateReducer.Result(state: .needsInput, attention: true))
}

@Test func needsInputWhileVisibleIsSeenImmediately() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .needsInput,
        isVisible: true,
        currentAttention: false
    )
    #expect(result == AgentStateReducer.Result(state: .needsInput, attention: false))
}

@Test func errorWhileHiddenRaisesAttention() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .error,
        isVisible: false,
        currentAttention: false
    )
    #expect(result == AgentStateReducer.Result(state: .error, attention: true))
}

@Test func runningDoesNotClearExistingAttention() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .running,
        isVisible: false,
        currentAttention: true
    )
    #expect(result == AgentStateReducer.Result(state: .running, attention: true))
}

@Test func visitingClearsAttentionOnAnyEvent() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .running,
        isVisible: true,
        currentAttention: true
    )
    #expect(result == AgentStateReducer.Result(state: .running, attention: false))
}
