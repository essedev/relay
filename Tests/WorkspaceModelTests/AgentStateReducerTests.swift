import AgentProtocol
import Testing
@testable import WorkspaceModel

@Test func idleToIdleIsNoiseFree() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .idle,
        currentAttention: .none
    )
    #expect(result == AgentStateReducer.Result(state: .idle, attention: .none))
}

@Test func idleToIdlePreservesPending() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .idle,
        currentAttention: .pending
    )
    #expect(result == AgentStateReducer.Result(state: .idle, attention: .pending))
}

/// Un completamento (running -> idle) nasce sempre col segnale forte (`unseen`), a prescindere
/// dalla visibilità: sulla tab in vista è il composition root a declassarlo a `pending` dopo un
/// breve flash (mark-read differito), non il reducer.
@Test func completedRaisesUnseenRegardlessOfVisibility() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .idle,
        currentAttention: .none
    )
    #expect(result == AgentStateReducer.Result(state: .idle, attention: .unseen))
}

/// needs_input è uno stato, non un marker: non usa `attention` (il badge lo mostra dallo stato,
/// e resta finché rispondi a Claude - non si spegne alla visita).
@Test func needsInputDoesNotUseAttention() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .needsInput,
        currentAttention: .none
    )
    #expect(result == AgentStateReducer.Result(state: .needsInput, attention: .none))
}

@Test func errorDoesNotUseAttention() {
    let result = AgentStateReducer.reduce(
        current: .running,
        incoming: .error,
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
        currentAttention: .unseen
    )
    #expect(result == AgentStateReducer.Result(state: .running, attention: .none))
}

@Test func runningResolvesPending() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .running,
        currentAttention: .pending
    )
    #expect(result == AgentStateReducer.Result(state: .running, attention: .none))
}

@Test func needsInputResolvesPending() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .needsInput,
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
        currentAttention: .unseen
    )
    #expect(unseen == AgentStateReducer.Result(state: .unknown, attention: .unseen))

    let pending = AgentStateReducer.reduce(
        current: .idle,
        incoming: .unknown,
        currentAttention: .pending
    )
    #expect(pending == AgentStateReducer.Result(state: .unknown, attention: .pending))
}

// MARK: - Ri-presa attiva (clear/resume) risolve il sospeso

/// Il caso centrale: dopo lo `Stop` la tab è già `idle` con un sospeso; un `/clear` arriva come
/// idle->idle e senza il flag lo preserverebbe (anti-rumore). Con `resetsAttention` lo spegne,
/// scavalcando l'anti-rumore.
@Test func resetResolvesPendingOnIdleToIdle() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .idle,
        currentAttention: .pending,
        resetsAttention: true
    )
    #expect(result == AgentStateReducer.Result(state: .idle, attention: .none))
}

/// Anche il segnale forte (`unseen`, es. `--resume` di una tab completata non vista) si spegne:
/// riaprire quella conversazione dimostra che te ne stai occupando.
@Test func resetResolvesUnseen() {
    let result = AgentStateReducer.reduce(
        current: .idle,
        incoming: .idle,
        currentAttention: .unseen,
        resetsAttention: true
    )
    #expect(result == AgentStateReducer.Result(state: .idle, attention: .none))
}

/// Una ri-presa non notifica mai, nemmeno se per caso arriva mentre lo stato era `running`
/// (`/clear` a metà lavoro): non è un completamento.
@Test func resetNeverNotifies() {
    #expect(AgentStateReducer.notification(
        current: .running, incoming: .idle, isVisible: false, resetsAttention: true
    ) == nil)
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
