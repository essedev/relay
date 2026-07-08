import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

// Le tre guardie di `applyAgentState` contro gli eventi che non devono toccare lo stato:
// monotonicità (consegna fuori ordine), soglia anti-stantio (hook eseguiti prima del boot) e
// fence di run (hook di sessioni orfane di run precedenti, eseguiti dopo il boot). Estratte da
// `AgentApplyTests` per il budget di dimensione file (vedi CONVENTIONS); fixture condivisa in
// `Fixtures.swift`.

// MARK: - Guardia di monotonicità (eventi consegnati fuori ordine)

/// Gli hook sono processi concorrenti: un evento può arrivare dopo uno più recente. Lo stantio va
/// scartato, non applicato: un running residuo non deve coprire il completamento già arrivato.
@Test @MainActor func staleEventIsDropped() {
    let fixture = makeAgentFixture()
    let tabID = fixture.hiddenTab.id.uuidString
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .running,
        at: Date(timeIntervalSince1970: 5)
    )
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(timeIntervalSince1970: 6))

    let applied = fixture.store.applyAgentState(
        paneId: tabID,
        state: .running,
        at: Date(timeIntervalSince1970: 5.5)
    )
    #expect(applied) // la tab esiste: l'evento è stato gestito (scartandolo)
    #expect(fixture.hiddenTab.agentState == .idle)
    #expect(fixture.hiddenTab.attention == .unseen)
    #expect(fixture.hiddenTab.lastEventAt == Date(timeIntervalSince1970: 6))
}

@Test @MainActor func staleEventDoesNotNotifyNorClearResume() {
    let fixture = makeAgentFixture()
    var emitted: [AgentNotification] = []
    fixture.store.onNotifiableTransition = { emitted.append($0) }
    let tabID = fixture.hiddenTab.id.uuidString
    fixture.store.applyAgentState(
        paneId: tabID,
        agent: "claude",
        sessionId: "s1",
        state: .running,
        at: Date(timeIntervalSince1970: 10)
    )
    #expect(fixture.hiddenTab.resume != nil)

    // SessionEnd in ritardo: non azzera il resume della sessione viva.
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .unknown,
        at: Date(timeIntervalSince1970: 9)
    )
    // needs_input in ritardo: niente notifica per uno stato ormai superato.
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .needsInput,
        at: Date(timeIntervalSince1970: 8)
    )
    #expect(fixture.hiddenTab.agentState == .running)
    #expect(fixture.hiddenTab.resume != nil)
    #expect(emitted.isEmpty)
}

@Test @MainActor func equalTimestampStillApplies() {
    // Due hook nello stesso millisecondo (granularità del wire): vince l'ultimo arrivato. La
    // guardia scarta solo lo strettamente più vecchio.
    let fixture = makeAgentFixture()
    let tabID = fixture.hiddenTab.id.uuidString
    let timestamp = Date(timeIntervalSince1970: 7)
    fixture.store.applyAgentState(paneId: tabID, state: .running, at: timestamp)
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: timestamp)
    #expect(fixture.hiddenTab.agentState == .idle)
}

// MARK: - Soglia anti-stantio (eventi generati prima dell'avvio)

/// Il `RELAY_TAB_ID` è stabile tra i riavvii: un `SessionEnd`/hook orfano di una sessione morta,
/// generato prima dell'avvio, arriverebbe con l'id di una tab ripristinata e ne azzererebbe il
/// resume binding. La soglia lo scarta, così la proposta di resume sopravvive; una ripresa vera
/// (post-avvio) passa e spegne il segnale.
@Test @MainActor func eventFloorProtectsRestoredResumeBinding() {
    let fixture = makeAgentFixture()
    let tab = fixture.hiddenTab
    let tabID = tab.id.uuidString
    // Tab ripristinata: binding presente, stato `unknown` -> pronta a proporre il resume.
    tab.resume = ResumeBinding(agent: "claude", sessionId: "s1", label: "t")
    #expect(tab.pendingResume)

    fixture.store.eventFloor = Date(timeIntervalSince1970: 100)

    // Evento fantasma pre-avvio: gestito (scartato), binding e stato intatti.
    let handled = fixture.store.applyAgentState(
        paneId: tabID, state: .unknown, at: Date(timeIntervalSince1970: 50)
    )
    #expect(handled)
    #expect(tab.resume != nil)
    #expect(tab.pendingResume)

    // Ripresa vera (oltre la soglia): passa e spegne la proposta.
    fixture.store.applyAgentState(
        paneId: tabID, state: .running, at: Date(timeIntervalSince1970: 150)
    )
    #expect(tab.agentState == .running)
    #expect(!tab.pendingResume)
}

@Test @MainActor func eventFloorAllowsEventsAtOrAfterTheThreshold() {
    let fixture = makeAgentFixture()
    let tabID = fixture.hiddenTab.id.uuidString
    fixture.store.eventFloor = Date(timeIntervalSince1970: 100)
    // Esattamente sulla soglia: passa (scartiamo solo lo strettamente più vecchio).
    fixture.store.applyAgentState(
        paneId: tabID, state: .running, at: Date(timeIntervalSince1970: 100)
    )
    #expect(fixture.hiddenTab.agentState == .running)
}

// MARK: - Fence di run (eventi di run precedenti eseguiti dopo l'avvio)

@Test @MainActor func runFenceDropsEventsFromOtherRuns() {
    let fixture = makeAgentFixture()
    let tab = fixture.hiddenTab
    let tabID = tab.id.uuidString
    // Tab ripristinata: binding presente, stato `unknown` -> pronta a proporre il resume.
    tab.resume = ResumeBinding(agent: "claude", sessionId: "s1", label: "t")
    fixture.store.runID = "run-a"

    // Hook di una sessione orfana di una run precedente: timestamp fresco (il floor non lo
    // fermerebbe), ma run diversa. Uno Stop (idle) non deve sopprimere la proposta di resume...
    let stop = fixture.store.applyAgentState(
        paneId: tabID, sessionId: "s1", runId: "run-z", state: .idle, at: Date()
    )
    #expect(stop)
    #expect(tab.agentState == .unknown)
    #expect(tab.pendingResume)

    // ...e un SessionEnd (unknown) non deve azzerare il binding.
    fixture.store.applyAgentState(
        paneId: tabID, sessionId: "s1", runId: "run-z", state: .unknown, at: Date()
    )
    #expect(tab.resume != nil)
    #expect(tab.pendingResume)
}

@Test @MainActor func runFenceDropsEventsWithoutRunId() {
    let fixture = makeAgentFixture()
    let tab = fixture.hiddenTab
    tab.resume = ResumeBinding(agent: "claude", sessionId: "s1", label: "t")
    fixture.store.runID = "run-a"
    // CLI vecchio o processo fuori dalle surface di questa run: nessun runId -> scartato.
    fixture.store.applyAgentState(
        paneId: tab.id.uuidString, sessionId: "s1", state: .unknown, at: Date()
    )
    #expect(tab.resume != nil)
    #expect(tab.pendingResume)
}

@Test @MainActor func runFenceAllowsMatchingRun() {
    let fixture = makeAgentFixture()
    let tab = fixture.hiddenTab
    tab.resume = ResumeBinding(agent: "claude", sessionId: "s1", label: "t")
    fixture.store.runID = "run-a"
    // Ripresa vera in questa run: passa e spegne la proposta.
    fixture.store.applyAgentState(
        paneId: tab.id.uuidString, sessionId: "s2", runId: "run-a", state: .running, at: Date()
    )
    #expect(tab.agentState == .running)
    #expect(!tab.pendingResume)
}

@Test @MainActor func runFenceOffAppliesAnyRun() {
    let fixture = makeAgentFixture()
    let tab = fixture.hiddenTab
    // Fence spento (store.runID nil): comportamento invariato, qualunque runId passa.
    fixture.store.applyAgentState(
        paneId: tab.id.uuidString, sessionId: "s1", runId: "run-z", state: .running, at: Date()
    )
    #expect(tab.agentState == .running)
}
