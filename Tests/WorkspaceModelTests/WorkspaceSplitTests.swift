import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

// Lo split visto dallo store: la Tab resta l'unità della sessione, il layout dice solo quali tab
// sono a schermo e quale ha il focus. Le due nozioni sono distinte e qui si separano.

@Test func splitFocusedPaneMountsANewTabAndFocusesIt() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay", rootPath: "/repo")
    let first = ws.tabs[0]
    first.currentDirectory = "/repo/Sources"

    let created = try #require(store.splitFocusedPane(axis: .horizontal))

    #expect(ws.tabs.count == 2)
    #expect(ws.mountedTabIDs == [first.id, created.id]) // ordine visivo
    #expect(ws.selectedTabID == created.id) // il nuovo pane prende il focus
    #expect(created.currentDirectory == "/repo/Sources") // eredita dal pane diviso
}

@Test func selectingAMountedTabOnlyMovesTheFocus() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .vertical))
    let layoutBefore = ws.splitLayout

    store.selectTab(first.id, in: ws)

    #expect(ws.selectedTabID == first.id)
    #expect(ws.splitLayout == layoutBefore) // il layout non si tocca
    #expect(ws.mountedTabIDs == [first.id, second.id])
}

@Test func selectingAnUnmountedTabTakesOverTheFocusedPane() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .horizontal)) // focused
    let third = store.addTab(to: ws) // non montata: entra al posto di `second`

    #expect(ws.mountedTabIDs == [first.id, third.id])
    #expect(ws.selectedTabID == third.id)
    #expect(ws.tabs.count == 3) // `second` è viva, solo smontata
    #expect(!ws.isMounted(second.id))
}

@Test func closingTheFocusedPaneKeepsTheTabAlive() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .horizontal))

    #expect(store.closeFocusedPane())

    #expect(ws.tabs.count == 2) // la tab non è stata chiusa: la sessione vive
    #expect(ws.splitLayout == nil) // una foglia sola = pane singolo (forma canonica)
    #expect(ws.selectedTabID == first.id)
    #expect(!ws.isMounted(second.id))
}

@Test func closingAPaneWithoutASplitIsANoOp() {
    let store = WorkspaceStore()
    store.createWorkspace(name: "relay")

    #expect(!store.closeFocusedPane()) // l'unico pane non si smonta: si chiude la tab
}

@Test func focusCyclesBetweenPanes() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .horizontal))

    #expect(store.focusAdjacentPane(forward: true))
    #expect(ws.selectedTabID == first.id) // ciclico
    #expect(store.focusAdjacentPane(forward: true))
    #expect(ws.selectedTabID == second.id)
    #expect(store.focusAdjacentPane(forward: false))
    #expect(ws.selectedTabID == first.id)
}

@Test func focusAdjacentPaneIsANoOpWithoutASplit() {
    let store = WorkspaceStore()
    store.createWorkspace(name: "relay")

    #expect(!store.focusAdjacentPane(forward: true))
}

@Test func closingAMountedTabCollapsesItsPaneAndMovesTheFocus() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .horizontal)) // focused

    store.closeTab(second.id, in: ws)

    #expect(ws.tabs.map(\.id) == [first.id])
    #expect(ws.splitLayout == nil)
    #expect(ws.selectedTabID == first.id)
}

@Test func closingAnUnmountedTabLeavesTheLayoutAlone() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .horizontal))
    let third = store.addTab(to: ws) // rimpiazza `second` nel pane focused
    #expect(!ws.isMounted(second.id))

    store.closeTab(second.id, in: ws) // tab viva ma smontata

    #expect(ws.mountedTabIDs == [first.id, third.id]) // layout intatto
    #expect(ws.tabs.count == 2)
}

@Test func setSplitRatioRewritesTheLayout() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    store.splitFocusedPane(axis: .horizontal)
    guard case let .split(branchID, _, _, _, _) = ws.splitLayout else {
        return #expect(Bool(false), "il workspace deve essere splittato")
    }

    store.setSplitRatio(0.7, forBranch: branchID, in: ws)

    guard case let .split(_, _, ratio, _, _) = ws.splitLayout else {
        return #expect(Bool(false), "il layout deve restare uno split")
    }
    #expect(ratio == 0.7)
}

// MARK: - Visibilità: montata, non solo focused

@Test func completionOnAMountedButUnfocusedPaneDoesNotBump() {
    // Con uno split guardi tutti i pane a schermo: un completamento su quello non focused non è
    // "arrivato mentre non guardavi", quindi niente bump del workspace e niente notifica.
    let store = WorkspaceStore()
    let other = store.createWorkspace(name: "altro")
    let ws = store.createWorkspace(name: "relay")
    let background = ws.tabs[0]
    store.splitFocusedPane(axis: .horizontal) // il nuovo pane è il focused
    store.selectWorkspace(ws.id)
    #expect(store.workspaces.map(\.id) == [other.id, ws.id])

    var notified = false
    store.onNotifiableTransition = { _ in notified = true }
    store.applyAgentState(paneId: background.id.uuidString, state: .running, at: Date())
    store.applyAgentState(paneId: background.id.uuidString, state: .idle, at: Date())

    #expect(!notified)
    #expect(store.workspaces.map(\.id) == [other.id, ws.id]) // nessun bump
}

@Test func completionOnAnUnmountedTabStillBumpsAndNotifies() {
    let store = WorkspaceStore()
    let other = store.createWorkspace(name: "altro")
    let ws = store.createWorkspace(name: "relay")
    let hidden = ws.tabs[0]
    store.splitFocusedPane(axis: .horizontal) // [hidden, nuovo], focus sul nuovo
    store.selectTab(hidden.id, in: ws) // focus su `hidden`, layout invariato
    store.addTab(to: ws) // la nuova tab prende il pane focused: `hidden` esce dallo schermo
    #expect(!ws.isMounted(hidden.id))
    store.selectWorkspace(ws.id)

    var notified = false
    store.onNotifiableTransition = { _ in notified = true }
    store.applyAgentState(paneId: hidden.id.uuidString, state: .running, at: Date())
    store.applyAgentState(paneId: hidden.id.uuidString, state: .idle, at: Date())

    #expect(notified) // una tab non a schermo è a tutti gli effetti "non vista"
    #expect(store.workspaces.map(\.id) == [ws.id, other.id]) // bumpata in cima
}

// MARK: - Persistence

@Test func splitLayoutSurvivesSnapshotAndRestore() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .vertical))

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())

    let workspace = restored.workspaces[0]
    #expect(workspace.mountedTabIDs == [first.id, second.id])
    #expect(workspace.selectedTabID == second.id)
    #expect(workspace.splitLayout == ws.splitLayout)
}

@Test func restoreDropsPanesWhoseTabIsGone() {
    // Snapshot con un layout che monta una tab inesistente (file editato a mano, corruzione
    // parziale): il pane orfano cade e il fratello prende il suo posto.
    let alive = TabSnapshot(id: UUID(), title: "t", hasCustomTitle: false, currentDirectory: nil)
    let ghost = UUID()
    let layout = SplitNode.leaf(alive.id)
        .splitting(alive.id, axis: .horizontal, with: ghost, branchID: UUID())
    let ws = WorkspaceSnapshot(
        id: UUID(), name: "w", rootPath: nil, pinned: false,
        selectedTabID: ghost, splitLayout: layout, tabs: [alive]
    )
    let store = WorkspaceStore()
    store.restore(from: LayoutSnapshot(selectedWorkspaceID: nil, workspaces: [ws]))

    let restored = store.workspaces[0]
    #expect(restored.splitLayout == nil) // una foglia sola: pane singolo
    #expect(restored.selectedTabID == alive.id) // la focused non resta appesa al fantasma
}

@Test func layoutsSavedBeforeSplitDecodeAsSinglePane() throws {
    // Campo additivo: un `WorkspaceSnapshot` senza `splitLayout` deve decodificare, non far
    // fallire l'intero layout dell'utente.
    let json = """
    {"id":"\(UUID().uuidString)","name":"w","rootPath":null,"pinned":false,
     "selectedTabID":null,"tabs":[]}
    """
    let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(json.utf8))

    #expect(decoded.splitLayout == nil)
}
