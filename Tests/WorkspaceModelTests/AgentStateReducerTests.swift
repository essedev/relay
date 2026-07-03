import AgentProtocol
import Testing
@testable import WorkspaceModel

@Test func idleToIdleIsNoiseFree() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .idle,
        isVisible: false,
        currentAttention: .none
    )
    #expect(result == AgentStateReducer.Result(state: .idle, attention: .none))
}

@Test func idleToIdlePreservesPending() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .idle,
        isVisible: true,
        currentAttention: .pending
    )
    #expect(result == AgentStateReducer.Result(state: .idle, attention: .pending))
}

@Test func completedWhileHiddenRaisesUnseen() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .idle,
        isVisible: false,
        currentAttention: .none
    )
    #expect(result == AgentStateReducer.Result(state: .idle, attention: .unseen))
}

/// Completare mentre guardi: la percezione è già avvenuta, il marker nasce direttamente "in
/// sospeso" (quieto). Non sparisce: se ti distrai senza riprendere, la dashboard lo ricorda.
@Test func completedWhileVisibleBecomesPending() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .idle,
        isVisible: true,
        currentAttention: .none
    )
    #expect(result == AgentStateReducer.Result(state: .idle, attention: .pending))
}

/// needs_input è uno stato, non un marker: non usa `attention` (il badge lo mostra dallo stato,
/// e resta finché rispondi a Claude - non si spegne alla visita).
@Test func needsInputDoesNotUseAttentionWhenHidden() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .needsInput,
        isVisible: false,
        currentAttention: .none
    )
    #expect(result == AgentStateReducer.Result(state: .needsInput, attention: .none))
}

@Test func needsInputDoesNotUseAttentionWhenVisible() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .needsInput,
        isVisible: true,
        currentAttention: .none
    )
    #expect(result == AgentStateReducer.Result(state: .needsInput, attention: .none))
}

@Test func errorDoesNotUseAttention() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .error,
        isVisible: false,
        currentAttention: .none
    )
    #expect(result == AgentStateReducer.Result(state: .error, attention: .none))
}

// MARK: - Risoluzione (la ripresa vera spegne il marker)

/// La conversazione che riparte (il tuo prompt -> running) è l'evento di risoluzione: spegne il
/// marker a qualunque livello, anche se non stai guardando la tab.
@Test func runningResolvesUnseen() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .running,
        isVisible: false,
        currentAttention: .unseen
    )
    #expect(result == AgentStateReducer.Result(state: .running, attention: .none))
}

@Test func runningResolvesPending() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .running,
        isVisible: true,
        currentAttention: .pending
    )
    #expect(result == AgentStateReducer.Result(state: .running, attention: .none))
}

@Test func needsInputResolvesPending() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .needsInput,
        isVisible: false,
        currentAttention: .pending
    )
    #expect(result == AgentStateReducer.Result(state: .needsInput, attention: .none))
}

/// Fine sessione (unknown): un completamento mai ripreso resta tale - la tab e il suo output
/// esistono ancora. Si spegne solo con dismiss, decadenza o chiusura tab.
@Test func sessionEndPreservesAttention() {
    let unseen = AgentStateReducer.reduce(
        current: .idle,
        incoming: .unknown,
        isVisible: false,
        currentAttention: .unseen
    )
    #expect(unseen == AgentStateReducer.Result(state: .unknown, attention: .unseen))

    let pending = AgentStateReducer.reduce(
        current: .idle,
        incoming: .unknown,
        isVisible: true,
        currentAttention: .pending
    )
    #expect(pending == AgentStateReducer.Result(state: .unknown, attention: .pending))
}

// MARK: - Classificatore notifiche

@Test func notifiesOnNeedsInputEntry() {
    #expect(AgentStateReducer.notification(
        current: .idle, incoming: .needsInput, isVisible: false
    ) == .needsInput)
    // Anche se la tab è in vista: la soppressione "la stai guardando" è runtime, non qui.
    #expect(AgentStateReducer.notification(
        current: .running, incoming: .needsInput, isVisible: true
    ) == .needsInput)
}

@Test func doesNotReNotifyNeedsInput() {
    #expect(AgentStateReducer.notification(
        current: .needsInput, incoming: .needsInput, isVisible: false
    ) == nil)
}

@Test func notifiesOnCompletedOnlyWhenHidden() {
    #expect(AgentStateReducer.notification(
        current: .running, incoming: .idle, isVisible: false
    ) == .completed)
    #expect(AgentStateReducer.notification(
        current: .running, incoming: .idle, isVisible: true
    ) == nil)
}

@Test func noNotificationOnIdleToIdleStartOrUnknown() {
    #expect(AgentStateReducer
        .notification(current: .idle, incoming: .idle, isVisible: false) == nil)
    #expect(AgentStateReducer
        .notification(current: .idle, incoming: .running, isVisible: false) == nil)
    #expect(AgentStateReducer
        .notification(current: .running, incoming: .unknown, isVisible: false) == nil)
}
