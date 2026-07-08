import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

// `applyAgentState` è il path che il coordinatore esegue per ogni evento: locate della tab via
// paneId, calcolo visibilità, reducer. Qui lo testiamo senza socket né app. La fixture è condivisa
// (vedi `Fixtures.swift`).

@Test @MainActor func needsInputSetsStateNotAttention() {
    let fixture = makeAgentFixture()
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
    let fixture = makeAgentFixture()
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
    let fixture = makeAgentFixture()
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

@Test @MainActor func completedOnVisibleTabRaisesUnseenAndSignalsFlash() {
    let fixture = makeAgentFixture()
    var flashed: [UUID] = []
    fixture.store.onVisibleCompletion = { flashed.append($0) }
    let tabID = fixture.visibleTab.id.uuidString
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .running,
        at: Date(timeIntervalSince1970: 1)
    )
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(timeIntervalSince1970: 2))
    #expect(fixture.visibleTab.agentState == .idle)
    // Anche guardando, il marker nasce forte (`unseen`: ring + flash + badge pieno); il
    // declassamento a "in sospeso" lo fa il composition root col mark-read differito, segnalato
    // qui da `onVisibleCompletion`.
    #expect(fixture.visibleTab.attention == .unseen)
    #expect(flashed == [fixture.visibleTab.id])
}

/// Un completamento non visto (tab nascosta) NON segnala il flash: resta forte finché non lo vedi,
/// senza timer di declassamento.
@Test @MainActor func completedOnHiddenTabDoesNotSignalFlash() {
    let fixture = makeAgentFixture()
    var flashed: [UUID] = []
    fixture.store.onVisibleCompletion = { flashed.append($0) }
    let tabID = fixture.hiddenTab.id.uuidString
    fixture.store.applyAgentState(
        paneId: tabID,
        state: .running,
        at: Date(timeIntervalSince1970: 1)
    )
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(timeIntervalSince1970: 2))
    #expect(fixture.hiddenTab.attention == .unseen)
    #expect(flashed.isEmpty)
}

/// `store.markSeen(id)` (target del timer di flash): declassa un `unseen` a `pending` e restamp
/// `attentionSince`; è un no-op su ogni altro livello (idempotente).
@Test @MainActor func markSeenByIdDeclassesUnseenOnly() {
    let fixture = makeAgentFixture()
    fixture.visibleTab.attention = .unseen
    fixture.store.markSeen(fixture.visibleTab.id)
    #expect(fixture.visibleTab.attention == .pending)
    // No-op su pending e none.
    fixture.store.markSeen(fixture.visibleTab.id)
    #expect(fixture.visibleTab.attention == .pending)
    fixture.hiddenTab.attention = .none
    fixture.store.markSeen(fixture.hiddenTab.id)
    #expect(fixture.hiddenTab.attention == .none)
    // Id inesistente: no-op, nessun crash.
    fixture.store.markSeen(UUID())
}

@Test func resumeBindingRejectsUnsafeComponents() {
    #expect(ResumeBinding.isSafeComponent("2bf36d53-b398-416f-9c05-1ae2c7964525"))
    #expect(ResumeBinding.isSafeComponent("claude"))
    #expect(!ResumeBinding.isSafeComponent("")) // sessione sconosciuta
    #expect(!ResumeBinding.isSafeComponent("id; rm -rf /")) // metacaratteri shell
    #expect(!ResumeBinding.isSafeComponent("$(whoami)"))
}

@Test @MainActor func unsafeSessionIdDoesNotCreateResume() {
    let fixture = makeAgentFixture()
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
    let fixture = makeAgentFixture()
    #expect(!fixture.store.applyAgentState(paneId: UUID().uuidString, state: .running, at: Date()))
}

@Test @MainActor func applyInvalidPaneIdIsNoOp() {
    let fixture = makeAgentFixture()
    #expect(!fixture.store.applyAgentState(paneId: "not-a-uuid", state: .running, at: Date()))
}

@Test @MainActor func emitsNeedsInputNotificationOnceOnEntry() {
    let fixture = makeAgentFixture()
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
    let fixture = makeAgentFixture()
    var emitted: [AgentNotification] = []
    fixture.store.onNotifiableTransition = { emitted.append($0) }
    let tabID = fixture.visibleTab.id.uuidString
    fixture.store.applyAgentState(paneId: tabID, state: .running, at: Date(), appActive: false)
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(), appActive: false)
    #expect(fixture.visibleTab.attention == .unseen) // completato non visto, anche se selezionata
    #expect(emitted.map(\.kind) == [.completed])
}

@Test @MainActor func activeAppOnSelectedTabRaisesUnseenWithoutNotifying() {
    // Relay in primo piano sulla tab in vista: completare non notifica (lo stai guardando). Il
    // marker nasce comunque forte (`unseen`, per il flash); il composition root lo declassa dopo.
    let fixture = makeAgentFixture()
    var emitted: [AgentNotification] = []
    fixture.store.onNotifiableTransition = { emitted.append($0) }
    let tabID = fixture.visibleTab.id.uuidString
    fixture.store.applyAgentState(paneId: tabID, state: .running, at: Date(), appActive: true)
    fixture.store.applyAgentState(paneId: tabID, state: .idle, at: Date(), appActive: true)
    #expect(fixture.visibleTab.attention == .unseen)
    #expect(emitted.isEmpty)
}

/// `/clear` o `/new`: SessionStart(clear) arriva come idle con `resetsAttention`. Un sospeso
/// residuo del completamento precedente si spegne, senza notificare.
@Test @MainActor func activeReEngagementClearsPending() {
    let fixture = makeAgentFixture()
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

/// Se completa mentre la stai guardando, la riga NON salta sotto le mani: il bump è gated su
/// `!isVisible` (indipendente dal livello del marker, che qui nasce `unseen` per il flash).
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
    #expect(c.tabs[0].attention == .unseen)
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

@Test @MainActor func emitsCompletedNotificationOnlyWhenHidden() {
    let fixture = makeAgentFixture()
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
