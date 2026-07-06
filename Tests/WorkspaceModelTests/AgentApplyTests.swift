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
    #expect(fixture.hiddenTab.attention == .none)
    #expect(fixture.hiddenTab.lastEventAt == Date(timeIntervalSince1970: 10))
}

@Test @MainActor func completedOnHiddenTabRaisesUnseen() {
    let fixture = makeFixture()
    let tabID = fixture.hiddenTab.id.uuidString
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .running,
        at: Date(timeIntervalSince1970: 1)
    )
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(timeIntervalSince1970: 2))
    #expect(fixture.hiddenTab.agentState == .idle)
    #expect(fixture.hiddenTab.attention == .unseen) // completato mentre non guardavi
    // Il marker timbra il proprio clock con l'evento che l'ha generato.
    #expect(fixture.hiddenTab.attentionSince == Date(timeIntervalSince1970: 2))
}

/// Un no-op (SessionEnd che preserva l'unseen) avanza `lastEventAt` per la monotonicità ma NON
/// ringiovanisce `attentionSince`: l'età del marker e la finestra di decadenza restano fedeli.
@Test @MainActor func noOpEventDoesNotRejuvenateMarkerClock() {
    let fixture = makeFixture()
    let tabID = fixture.hiddenTab.id.uuidString
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .running,
        at: Date(timeIntervalSince1970: 1)
    )
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(timeIntervalSince1970: 2))
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .unknown,
        at: Date(timeIntervalSince1970: 99)
    )
    #expect(fixture.hiddenTab.attention == .unseen) // SessionEnd preserva il completamento
    #expect(fixture.hiddenTab.attentionSince == Date(timeIntervalSince1970: 2)) // clock invariato
    #expect(fixture.hiddenTab.lastEventAt == Date(timeIntervalSince1970: 99)) // monotonicità avanza
}

@Test @MainActor func completedOnVisibleTabBecomesPending() {
    let fixture = makeFixture()
    let tabID = fixture.visibleTab.id.uuidString
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .running,
        at: Date(timeIntervalSince1970: 1)
    )
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(timeIntervalSince1970: 2))
    #expect(fixture.visibleTab.agentState == .idle)
    // Guardavi: percezione già avvenuta -> "in sospeso" (quieto), non forte.
    #expect(fixture.visibleTab.attention == .pending)
}

@Test func resumeBindingRejectsUnsafeComponents() {
    #expect(ResumeBinding.isSafeComponent("2bf36d53-b398-416f-9c05-1ae2c7964525"))
    #expect(ResumeBinding.isSafeComponent("claude"))
    #expect(!ResumeBinding.isSafeComponent("")) // sessione sconosciuta
    #expect(!ResumeBinding.isSafeComponent("id; rm -rf /")) // metacaratteri shell
    #expect(!ResumeBinding.isSafeComponent("$(whoami)"))
}

@Test @MainActor func unsafeSessionIdDoesNotCreateResume() {
    let fixture = makeFixture()
    fixture.store.applyAgentState(
        paneId: fixture.hiddenTab.id.uuidString,
        agent: "claude",
        sessionId: "bad; rm -rf /",
        state: .running,
        at: Date()
    )
    #expect(fixture.hiddenTab.resume == nil) // niente binding iniettabile nel pty
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
    #expect(fixture.visibleTab.attention == .unseen) // completato non visto, anche se selezionata
    #expect(emitted.map(\.kind) == [.completed])
}

@Test @MainActor func activeAppOnSelectedTabGoesPendingWithoutNotifying() {
    // Relay in primo piano sulla tab in vista: completare non notifica (lo stai guardando);
    // il marker nasce quieto ("in sospeso"), non forte.
    let fixture = makeFixture()
    var emitted: [AgentNotification] = []
    fixture.store.onNotifiableTransition = { emitted.append($0) }
    let tabID = fixture.visibleTab.id.uuidString
    fixture.store.applyAgentState(paneId: tabID, state: .running, at: Date(), appActive: true)
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(), appActive: true)
    #expect(fixture.visibleTab.attention == .pending)
    #expect(emitted.isEmpty)
}

/// `/clear` o `/new`: SessionStart(clear) arriva come idle con `resetsAttention`. Un sospeso
/// residuo del completamento precedente si spegne, senza notificare.
@Test @MainActor func activeReEngagementClearsPending() {
    let fixture = makeFixture()
    var emitted: [AgentNotification] = []
    fixture.store.onNotifiableTransition = { emitted.append($0) }
    let tabID = fixture.hiddenTab.id.uuidString
    // Completamento non visto -> unseen.
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .running,
        at: Date(timeIntervalSince1970: 1)
    )
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(timeIntervalSince1970: 2))
    #expect(fixture.hiddenTab.attention == .unseen)
    emitted.removeAll()

    // /clear: idle con re-engagement -> marker spento, nessuna notifica.
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .idle,
        at: Date(timeIntervalSince1970: 3),
        resetsAttention: true
    )
    #expect(fixture.hiddenTab.agentState == .idle)
    #expect(fixture.hiddenTab.attention == .none)
    #expect(emitted.isEmpty)
}

// MARK: - Bump posizionale (modello lista chat: l'attività non vista sale in cima)

/// Un completamento arrivato mentre non guardavi porta il workspace in cima ai non-pinned:
/// riordino reale dell'ordine canonico, non un float derivato.
@Test @MainActor func completionOnHiddenTabBumpsToTop() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    _ = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")
    store.selectWorkspace(a.id) // a in vista; b, c nascoste
    let cTab = c.tabs[0].id.uuidString
    store.applyAgentState(paneId: cTab, state: .running, at: Date(timeIntervalSince1970: 1))
    store.applyAgentState(paneId: cTab, state: .idle, at: Date(timeIntervalSince1970: 2))
    #expect(store.orderedWorkspaces.map(\.name) == ["c", "a", "b"])
}

/// Se completa mentre la stai guardando, la riga NON salta sotto le mani: la percezione è già
/// avvenuta (il marker nasce quieto, `pending`).
@Test @MainActor func completionOnVisibleTabDoesNotBump() {
    let store = WorkspaceStore()
    _ = store.createWorkspace(name: "a")
    _ = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")
    store.selectWorkspace(c.id) // c in vista, in fondo
    let cTab = c.tabs[0].id.uuidString
    store.applyAgentState(paneId: cTab, state: .running, at: Date(timeIntervalSince1970: 1))
    store.applyAgentState(paneId: cTab, state: .idle, at: Date(timeIntervalSince1970: 2))
    #expect(store.orderedWorkspaces.map(\.name) == ["a", "b", "c"]) // resta dov'è
    #expect(c.tabs[0].attention == .pending)
}

/// L'entrata in `needs_input` mentre non guardavi bumpa come il completamento.
@Test @MainActor func needsInputOnHiddenTabBumpsToTop() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    _ = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")
    store.selectWorkspace(a.id)
    store.applyAgentState(
        paneId: c.tabs[0].id.uuidString, state: .needsInput, at: Date(timeIntervalSince1970: 1)
    )
    #expect(store.orderedWorkspaces.map(\.name) == ["c", "a", "b"])
}

/// Il caso da cui siamo partiti: prendi una riga salita in cima e ci scrivi (`running`). Il marker
/// si spegne (ripresa), ma la posizione NON cambia: niente scivolamento sotto le mani.
@Test @MainActor func resumeDoesNotDropFromTop() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    store.selectWorkspace(a.id)
    let bTab = b.tabs[0].id.uuidString
    store.applyAgentState(paneId: bTab, state: .running, at: Date(timeIntervalSince1970: 1))
    store.applyAgentState(paneId: bTab, state: .idle, at: Date(timeIntervalSince1970: 2))
    #expect(store.orderedWorkspaces.map(\.name) == ["b", "a"]) // b è salita

    store.selectWorkspace(b.id) // ora la guardi e ci scrivi
    store.applyAgentState(paneId: bTab, state: .running, at: Date(timeIntervalSince1970: 3))
    #expect(store.orderedWorkspaces.map(\.name) == ["b", "a"]) // resta su
    #expect(b.tabs[0].attention == .none) // marker spento, posizione invariata
}

/// Il bump rispetta il blocco pinned: sale in cima ai NON-pinned, sotto i pinned.
@Test @MainActor func bumpLandsBelowPinned() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")
    store.togglePin(a.id) // a pinnato in testa
    store.selectWorkspace(b.id) // b in vista; c nascosta
    let cTab = c.tabs[0].id.uuidString
    store.applyAgentState(paneId: cTab, state: .running, at: Date(timeIntervalSince1970: 1))
    store.applyAgentState(paneId: cTab, state: .idle, at: Date(timeIntervalSince1970: 2))
    #expect(store.orderedWorkspaces.map(\.name) == ["a", "c", "b"])
}

// MARK: - Guardia di monotonicità (eventi consegnati fuori ordine)

/// Gli hook sono processi concorrenti: un evento può arrivare dopo uno più recente. Lo stantio va
/// scartato, non applicato: un running residuo non deve coprire il completamento già arrivato.
@Test @MainActor func staleEventIsDropped() {
    let fixture = makeFixture()
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
    let fixture = makeFixture()
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
    let fixture = makeFixture()
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
    let fixture = makeFixture()
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
    let fixture = makeFixture()
    let tabID = fixture.hiddenTab.id.uuidString
    fixture.store.eventFloor = Date(timeIntervalSince1970: 100)
    // Esattamente sulla soglia: passa (scartiamo solo lo strettamente più vecchio).
    fixture.store.applyAgentState(
        paneId: tabID, state: .running, at: Date(timeIntervalSince1970: 100)
    )
    #expect(fixture.hiddenTab.agentState == .running)
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
