import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

// Le finestre partizionano i workspace: uno store solo, N finestre, ognuna con la sua selezione.
// Nessuna finestra è privilegiata; chiuderne una rimpatria il lavoro invece di distruggerlo.

@Test func aFreshStoreHasOneWindowThatOwnsEverything() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")

    #expect(store.windows.count == 1)
    #expect(store.keyWindowID == RelayWindow.mainID)
    #expect(ws.windowID == RelayWindow.mainID)
    #expect(store.selectedWorkspaceID == ws.id) // proiezione della finestra key
}

@Test func eachWindowKeepsItsOwnSelection() throws {
    let store = WorkspaceStore()
    let first = store.createWorkspace(name: "a")
    let second = store.createWorkspace(name: "b")

    let window = try #require(store.moveWorkspaceToNewWindow(second.id))

    #expect(second.windowID == window.id)
    #expect(store.keyWindowID == window.id) // la nuova finestra prende il focus
    #expect(store.selectedWorkspace(in: window.id)?.id == second.id)
    #expect(store.selectedWorkspace(in: RelayWindow.mainID)?.id == first.id)
    // Ogni sidebar vede solo i suoi.
    #expect(store.orderedWorkspaces(in: RelayWindow.mainID).map(\.id) == [first.id])
    #expect(store.orderedWorkspaces(in: window.id).map(\.id) == [second.id])
}

@Test func movingTheOnlyWorkspaceOfAWindowIsANoOp() {
    // Lascerebbe la finestra di partenza senza niente da mostrare.
    let store = WorkspaceStore()
    let only = store.createWorkspace(name: "solo")

    #expect(store.moveWorkspaceToNewWindow(only.id) == nil)
    #expect(store.windows.count == 1)
}

@Test func movingAWorkspaceDoesNotTouchItsTabs() throws {
    // Le surface sono legate per `Tab.id`: spostare un workspace di finestra non deve ricrearle.
    let store = WorkspaceStore()
    store.createWorkspace(name: "a")
    let moved = store.createWorkspace(name: "b")
    let tabIDs = moved.tabs.map(\.id)

    try #require(store.moveWorkspaceToNewWindow(moved.id))

    #expect(moved.tabs.map(\.id) == tabIDs)
}

@Test func closingAWindowRepatriatesItsWorkspaces() throws {
    let store = WorkspaceStore()
    let stay = store.createWorkspace(name: "a")
    let moved = store.createWorkspace(name: "b")
    let window = try #require(store.moveWorkspaceToNewWindow(moved.id))

    let repatriated = store.closeWindow(window.id)

    #expect(repatriated == [moved.id])
    #expect(moved.windowID == RelayWindow.mainID) // il lavoro non si butta con la finestra
    #expect(store.windows.count == 1)
    #expect(store.keyWindowID == RelayWindow.mainID)
    #expect(store.workspaces(in: RelayWindow.mainID).map(\.id) == [stay.id, moved.id])
}

@Test func closingTheLastWindowIsANoOp() {
    // L'ultima finestra la chiude l'app: il layout va salvato com'è.
    let store = WorkspaceStore()
    store.createWorkspace(name: "a")

    #expect(store.closeWindow(RelayWindow.mainID).isEmpty)
    #expect(store.windows.count == 1)
}

@Test func closingAWindowHandsOverToTheMostRecentlyActivatedOne() throws {
    let store = WorkspaceStore()
    let first = store.createWorkspace(name: "a")
    let second = store.createWorkspace(name: "b")
    let third = store.createWorkspace(name: "c")
    let windowB = try #require(store.moveWorkspaceToNewWindow(second.id))
    let windowC = try #require(store.moveWorkspaceToNewWindow(third.id))
    store.activateWindow(windowB.id) // B è la più recente fra le superstiti

    store.closeWindow(windowC.id)

    #expect(third.windowID == windowB.id) // rimpatriato nella più recente, non nella prima
    #expect(store.keyWindowID == windowB.id)
    #expect(first.windowID == RelayWindow.mainID) // le altre non si toccano
}

@Test func selectingAWorkspaceFromAnotherWindowActivatesThatWindow() throws {
    let store = WorkspaceStore()
    store.createWorkspace(name: "a")
    let moved = store.createWorkspace(name: "b")
    let window = try #require(store.moveWorkspaceToNewWindow(moved.id))
    store.activateWindow(RelayWindow.mainID)

    store.selectWorkspace(moved.id) // es. click su una notifica, o jump dalla dashboard

    #expect(store.keyWindowID == window.id) // si va dov'è il workspace, non lo si trascina qui
    #expect(store.selectedWorkspaceID == moved.id)
}

@Test func closingAWorkspaceMovesTheSelectionWithinItsOwnWindow() throws {
    let store = WorkspaceStore()
    let stay = store.createWorkspace(name: "a")
    let first = store.createWorkspace(name: "b")
    let second = store.createWorkspace(name: "c")
    let window = try #require(store.moveWorkspaceToNewWindow(first.id))
    store.moveWorkspace(second.id, toWindow: window.id) // due workspace nella finestra nuova
    store.selectWorkspace(second.id)

    store.closeWorkspace(second.id)

    // La finestra ripiega su un suo workspace, mai su quello di un'altra finestra.
    #expect(window.selectedWorkspaceID == first.id)
    #expect(store.selectedWorkspace(in: RelayWindow.mainID)?.id == stay.id)
}

// MARK: - Visibilità: la finestra a schermo, non quella col focus

@Test func aCompletionInAVisibleButUnfocusedWindowDoesNotNotify() throws {
    // Il caso d'uso del multi-window: due monitor, guardi la finestra che non ha il focus.
    let store = WorkspaceStore()
    store.createWorkspace(name: "a")
    let watched = store.createWorkspace(name: "b")
    let tab = watched.tabs[0]
    let window = try #require(store.moveWorkspaceToNewWindow(watched.id))
    store.activateWindow(RelayWindow.mainID) // il focus è altrove, ma la finestra è a schermo
    #expect(store.keyWindowID != window.id)

    var notified = false
    store.onNotifiableTransition = { _ in notified = true }
    store.applyAgentState(paneId: tab.id.uuidString, state: .running, at: Date())
    store.applyAgentState(paneId: tab.id.uuidString, state: .idle, at: Date())

    #expect(!notified) // la stai guardando: niente banner
    #expect(tab.attention == .unseen) // il marker nasce comunque forte (lo declassa il flash)
}

@Test func aCompletionInAnOccludedWindowNotifiesAndBumps() throws {
    let store = WorkspaceStore()
    let other = store.createWorkspace(name: "a")
    let hidden = store.createWorkspace(name: "b")
    let sibling = store.createWorkspace(name: "c")
    let tab = hidden.tabs[0]
    let window = try #require(store.moveWorkspaceToNewWindow(hidden.id))
    store.moveWorkspace(sibling.id, toWindow: window.id) // due workspace: il bump ha dove muoversi
    store.occludedWindowIDs.insert(window.id) // finestra coperta o minimizzata

    var notified = false
    store.onNotifiableTransition = { _ in notified = true }
    store.applyAgentState(paneId: tab.id.uuidString, state: .running, at: Date())
    store.applyAgentState(paneId: tab.id.uuidString, state: .idle, at: Date())

    #expect(notified)
    #expect(other.windowID == RelayWindow.mainID)
    // Il bump riordina dentro la sua finestra, non strappa il workspace in testa alla lista
    // globale.
    #expect(store.orderedWorkspaces(in: window.id).first?.id == hidden.id)
}

@Test func aCompletionInAWorkspaceNotShownByItsWindowNotifies() {
    // La finestra è a schermo ma mostra un altro workspace: quella tab non la vedi.
    let store = WorkspaceStore()
    let shown = store.createWorkspace(name: "a")
    let background = store.createWorkspace(name: "b")
    let tab = background.tabs[0]
    store.selectWorkspace(shown.id)

    var notified = false
    store.onNotifiableTransition = { _ in notified = true }
    store.applyAgentState(paneId: tab.id.uuidString, state: .running, at: Date())
    store.applyAgentState(paneId: tab.id.uuidString, state: .idle, at: Date())

    #expect(notified)
}

// MARK: - Persistence

@Test func windowsSurviveSnapshotAndRestore() throws {
    let store = WorkspaceStore()
    let first = store.createWorkspace(name: "a")
    let second = store.createWorkspace(name: "b")
    let window = try #require(store.moveWorkspaceToNewWindow(second.id))
    store.setWindowFrame(WindowFrame(x: 10, y: 20, width: 800, height: 600), for: window.id)

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())

    #expect(restored.windows.count == 2)
    #expect(restored.keyWindowID == window.id) // la key torna key
    #expect(restored.workspaces(in: window.id).map(\.id) == [second.id])
    #expect(restored.workspaces(in: RelayWindow.mainID).map(\.id) == [first.id])
    #expect(restored.windows.first { $0.id == window.id }?.frame?.width == 800)
}

@Test func layoutsSavedBeforeMultiWindowRestoreIntoASingleWindow() throws {
    // Campo additivo: nessun `windows`, nessun `windowID`. Tutto finisce nella finestra principale.
    let tab = TabSnapshot(id: UUID(), title: "t", hasCustomTitle: false, currentDirectory: nil)
    let wsID = UUID()
    let json = """
    {"version":1,"selectedWorkspaceID":"\(wsID.uuidString)","workspaces":[
      {"id":"\(wsID.uuidString)","name":"w","rootPath":null,"pinned":false,
       "selectedTabID":"\(tab.id.uuidString)","tabs":[
         {"id":"\(tab.id.uuidString)","title":"t","hasCustomTitle":false}]}]}
    """
    let snapshot = try JSONDecoder().decode(LayoutSnapshot.self, from: Data(json.utf8))
    let store = WorkspaceStore()
    store.restore(from: snapshot)

    #expect(store.windows.count == 1)
    #expect(store.keyWindowID == RelayWindow.mainID)
    #expect(store.workspaces[0].windowID == RelayWindow.mainID)
    #expect(store.selectedWorkspaceID == wsID)
}

@Test func restoreDropsWindowsThatOwnNoWorkspace() {
    // Una finestra senza workspace non ha niente da mostrare: cade.
    let store = WorkspaceStore()
    let only = store.createWorkspace(name: "a")
    var snapshot = store.snapshot()
    snapshot.windows.append(WindowSnapshot(id: UUID(), selectedWorkspaceID: nil))

    let restored = WorkspaceStore()
    restored.restore(from: snapshot)

    #expect(restored.windows.count == 1)
    #expect(restored.selectedWorkspaceID == only.id)
}

@Test func restoreRehomesWorkspacesWhoseWindowIsGone() {
    // File editato a mano: un workspace punta a una finestra che non esiste. Meglio una sidebar
    // sbagliata che un workspace invisibile per sempre.
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "a")
    var snapshot = store.snapshot()
    snapshot.workspaces[0].windowID = UUID()

    let restored = WorkspaceStore()
    restored.restore(from: snapshot)

    #expect(restored.workspaces.count == 1)
    #expect(restored.workspaces[0].windowID == restored.windows[0].id)
    #expect(restored.selectedWorkspace?.id == ws.id)
}

@Test func createWorkspaceWithoutSelectKeepsTheOriginSelection() {
    // Il percorso di New Window: il workspace transitorio nasce nella finestra corrente senza
    // diventarne la selezione, così dopo la migrazione la finestra d'origine resta sulla riga
    // su cui stavi lavorando (prima ripiegava sul primo della sidebar).
    let store = WorkspaceStore()
    store.createWorkspace(name: "A")
    let current = store.createWorkspace(name: "B") // selezionato
    let transient = store.createWorkspace(name: "C", select: false)

    #expect(store.selectedWorkspaceID == current.id) // la selezione non si è mossa

    let window = store.moveWorkspaceToNewWindow(transient.id)
    #expect(window != nil)
    #expect(window?.selectedWorkspaceID == transient.id) // la nuova finestra lo mostra
    // La finestra d'origine è rimasta dov'era.
    let origin = store.windows.first { $0.id == RelayWindow.mainID }
    #expect(origin?.selectedWorkspaceID == current.id)
}
