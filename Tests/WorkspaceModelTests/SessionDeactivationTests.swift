import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

// Disattivare una sessione significa spegnere il processo **tenendo** il punto a cui tornare. La
// parte fragile non è marcare la tab, è che gli ultimi hook della sessione che stiamo uccidendo
// arrivano dopo il kill: un `SessionEnd` azzererebbe il binding e uno `Stop` in ritardo
// rimetterebbe la tab in piedi da sola. Questi test difendono quella finestra.

@MainActor
private func makeDeactivationFixture() -> (store: WorkspaceStore, tab: Tab) {
    let store = WorkspaceStore()
    let visible = store.createWorkspace(name: "A")
    let hidden = store.createWorkspace(name: "B")
    store.selectWorkspace(visible.id)
    let tab = hidden.tabs[0]
    store.applyAgentState(
        paneId: tab.id.uuidString,
        agent: "claude",
        sessionId: "session-one",
        state: .idle,
        at: Date(timeIntervalSince1970: 10)
    )
    return (store, tab)
}

// MARK: - Eleggibilità

@Test @MainActor func aTabOnScreenIsNeverDeactivated() {
    let (_, tab) = makeDeactivationFixture()
    #expect(tab.deactivationBlock(isOnScreen: true) == .onScreen)
}

@Test @MainActor func aWorkingAgentIsLeftAlone() {
    let (store, tab) = makeDeactivationFixture()
    store.applyAgentState(
        paneId: tab.id.uuidString,
        agent: "claude",
        sessionId: "session-one",
        state: .running,
        at: Date(timeIntervalSince1970: 20)
    )
    #expect(tab.deactivationBlock(isOnScreen: false) == .working)
}

@Test @MainActor func aTabWithoutASessionHasNothingToComeBackTo() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "A")
    #expect(workspace.tabs[0].deactivationBlock(isOnScreen: false) == .noSession)
}

@Test @MainActor func anIdleAgentOffScreenIsDeactivatable() {
    let (_, tab) = makeDeactivationFixture()
    #expect(tab.deactivationBlock(isOnScreen: false) == nil)
}

// MARK: - Il comando

@Test @MainActor func deactivationKeepsTheBindingAndClearsTheLiveState() {
    let (store, tab) = makeDeactivationFixture()
    let done = store.deactivate([tab.id])
    #expect(done == [tab.id])
    #expect(tab.deactivated)
    #expect(tab.resume?.sessionId == "session-one")
    // Come dopo un riavvio: nessuna sessione viva, un resume da proporre.
    #expect(tab.agentState == .unknown)
    #expect(tab.pendingResume)
}

@Test @MainActor func deactivationSkipsTabsWithoutABinding() {
    let store = WorkspaceStore()
    let workspace = store.createWorkspace(name: "A")
    #expect(store.deactivate([workspace.tabs[0].id]).isEmpty)
    #expect(!workspace.tabs[0].deactivated)
}

// MARK: - Gli hook della sessione morente

@Test @MainActor func theDyingSessionEndDoesNotDropTheBinding() {
    let (store, tab) = makeDeactivationFixture()
    store.deactivate([tab.id])
    // `SessionEnd` -> `unknown`: su una tab normale azzera il resume. Qui è l'eco del kill.
    store.applyAgentState(
        paneId: tab.id.uuidString,
        agent: "claude",
        sessionId: "session-one",
        state: .unknown,
        at: Date(timeIntervalSince1970: 30)
    )
    #expect(tab.resume?.sessionId == "session-one")
    #expect(tab.deactivated)
}

@Test @MainActor func aNormalSessionEndStillDropsTheBinding() {
    let (store, tab) = makeDeactivationFixture()
    store.applyAgentState(
        paneId: tab.id.uuidString,
        agent: "claude",
        sessionId: "session-one",
        state: .unknown,
        at: Date(timeIntervalSince1970: 30)
    )
    #expect(tab.resume == nil)
}

@Test @MainActor func aLateStopFromTheKilledSessionDoesNotRevive() {
    let (store, tab) = makeDeactivationFixture()
    store.deactivate([tab.id])
    // Gli hook sono processi concorrenti: uno `Stop` può atterrare dopo il kill.
    store.applyAgentState(
        paneId: tab.id.uuidString,
        agent: "claude",
        sessionId: "session-one",
        state: .idle,
        at: Date(timeIntervalSince1970: 30)
    )
    #expect(tab.deactivated)
}

@Test @MainActor func aSessionStartedAfterwardsClearsTheMarker() {
    let (store, tab) = makeDeactivationFixture()
    store.deactivate([tab.id])
    // L'utente ha lanciato un agente a mano nella tab spenta: è di nuovo una tab viva.
    store.applyAgentState(
        paneId: tab.id.uuidString,
        agent: "claude",
        sessionId: "session-two",
        state: .running,
        at: Date(timeIntervalSince1970: 40)
    )
    #expect(!tab.deactivated)
    #expect(tab.resume?.sessionId == "session-two")
}

// MARK: - Cosa si propone al focus

@Test @MainActor func aDeactivatedTabNeverResumesOnItsOwn() {
    let (store, tab) = makeDeactivationFixture()
    store.deactivate([tab.id])
    // Con l'auto-resume acceso, aprire una tab spenta anche solo per leggerla rimetterebbe in
    // piedi l'agente appena spento: il risparmio evaporerebbe durante il triage.
    #expect(tab.resumePresentation(autoResume: true) == .bar)
    #expect(tab.resumePresentation(autoResume: false) == .bar)
}

@Test @MainActor func aTabRestoredFromDiskStillAutoResumes() {
    // L'auto-resume esiste per il riavvio, che e' involontario: li' non si tocca.
    let (store, tab) = makeDeactivationFixture()
    store.applyAgentState(
        paneId: tab.id.uuidString,
        agent: "claude",
        sessionId: "session-one",
        state: .unknown,
        at: Date(timeIntervalSince1970: 30)
    )
    tab.resume = ResumeBinding(agent: "claude", sessionId: "session-one", label: "x")
    #expect(tab.resumePresentation(autoResume: true) == .inject)
    #expect(tab.resumePresentation(autoResume: false) == .bar)
}

@Test @MainActor func aTabWithALiveSessionProposesNothing() {
    let (_, tab) = makeDeactivationFixture()
    #expect(tab.agentState == .idle)
    #expect(tab.resumePresentation(autoResume: true) == .none)
}

@Test @MainActor func resumingFromTheBarClearsTheMarker() {
    let (store, tab) = makeDeactivationFixture()
    store.deactivate([tab.id])
    store.clearDeactivation(tab.id)
    #expect(!tab.deactivated)
}

// MARK: - Montaggio e persistenza

@Test @MainActor func onlyTheWorkspaceOnScreenCountsAsMounted() {
    let store = WorkspaceStore()
    let visible = store.createWorkspace(name: "A")
    let hidden = store.createWorkspace(name: "B")
    store.selectWorkspace(visible.id)
    #expect(store.isMounted(visible.tabs[0].id))
    #expect(!store.isMounted(hidden.tabs[0].id))
}

@Test @MainActor func deactivationSurvivesARestart() {
    let (store, tab) = makeDeactivationFixture()
    store.deactivate([tab.id])

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())
    let tabs = restored.workspaces.flatMap(\.tabs)
    let reloaded = tabs.first { $0.id == tab.id }
    // Senza questo, al primo focus `autoResumeAgents` rimetterebbe in piedi proprio le sessioni
    // appena spente.
    #expect(reloaded?.deactivated == true)
    #expect(reloaded?.resume?.sessionId == "session-one")
}

@Test func aLayoutSavedBeforeTheFeatureDecodesAsActive() throws {
    // Campo additivo: la sintesi lo esigerebbe come chiave e farebbe fallire il decode dell'intero
    // layout salvato prima della feature, cioè buttare via il layout dell'utente.
    let json = """
    {"id":"\(UUID().uuidString)","title":"shell","hasCustomTitle":false}
    """
    let snapshot = try JSONDecoder().decode(TabSnapshot.self, from: Data(json.utf8))
    #expect(!snapshot.deactivated)
}
