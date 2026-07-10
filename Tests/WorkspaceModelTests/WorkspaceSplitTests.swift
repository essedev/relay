import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

// Lo split visto dallo store (modello cmux): le tab vivono nei pane, a schermo c'è la selezionata
// di ogni strip, il focus è di un pane. La Tab resta l'unità della sessione: montare, spostare o
// selezionare non ne tocca l'identità.

@Test func splitFocusedPaneOpensANewTabInANewPaneAndFocusesIt() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay", rootPath: "/repo")
    let first = ws.tabs[0]
    first.currentDirectory = "/repo/Sources"

    let created = try #require(store.splitFocusedPane(axis: .horizontal))

    #expect(ws.tabs.count == 2)
    #expect(ws.visibleTabIDs == [first.id, created.id]) // entrambe a schermo, ordine visivo
    #expect(ws.selectedTabID == created.id) // il nuovo pane prende il focus
    #expect(ws.layout.paneIDs.count == 2)
    #expect(created.currentDirectory == "/repo/Sources") // eredita dal pane diviso
}

@Test func selectingATabInAnotherPaneMovesTheFocusThere() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .vertical))
    let layoutBefore = ws.layout

    store.selectTab(first.id, in: ws)

    #expect(ws.selectedTabID == first.id)
    #expect(ws.focusedPaneID == ws.layout.paneID(containing: first.id))
    #expect(ws.layout == layoutBefore) // selezionare non muta mai la struttura
    #expect(ws.visibleTabIDs == [first.id, second.id])
}

@Test func newTabJoinsTheFocusedPaneStrip() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .horizontal)) // pane B focused

    let third = store.addTab(to: ws) // nella strip del pane B, selezionata

    #expect(ws.tabs.count == 3)
    #expect(ws.layout.paneIDs.count == 2) // nessun pane nuovo
    #expect(ws.layout.paneID(containing: third.id) == ws.layout.paneID(containing: second.id))
    #expect(ws.visibleTabIDs == [first.id, third.id]) // `second` resta nella strip, nascosta
    #expect(ws.isVisible(first.id) && ws.isVisible(third.id) && !ws.isVisible(second.id))
}

@Test func closingAPaneKillsItsTabs() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .horizontal))
    let third = store.addTab(to: ws) // stessa strip di `second`

    let removed = store.closeFocusedPane()

    #expect(Set(removed) == Set([second.id, third.id])) // le tab muoiono col pane
    #expect(ws.tabs.map(\.id) == [first.id])
    #expect(ws.layout.paneIDs.count == 1)
    #expect(ws.selectedTabID == first.id) // il focus passa al fratello
}

@Test func closingTheOnlyPaneIsANoOp() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")

    #expect(store.closeFocusedPane().isEmpty) // l'unico pane non si chiude: si chiude la tab
    #expect(ws.tabs.count == 1)
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

@Test func closingTheLastTabOfAPaneCollapsesIt() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .horizontal)) // focused, sola nel pane

    store.closeTab(second.id, in: ws)

    #expect(ws.tabs.map(\.id) == [first.id])
    #expect(ws.layout.paneIDs.count == 1)
    #expect(ws.selectedTabID == first.id) // il focus passa al pane rimasto
}

@Test func closingAVisibleTabRevealsItsStripNeighbor() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let second = try #require(store.splitFocusedPane(axis: .horizontal))
    let third = store.addTab(to: ws) // strip del pane B: [second, third], visibile third

    store.closeTab(third.id, in: ws)

    // Il pane sopravvive con `second`, che torna a schermo (selezione index-stable).
    #expect(ws.layout.paneIDs.count == 2)
    #expect(ws.isVisible(second.id))
    #expect(ws.selectedTabID == second.id)
}

@Test func closingAHiddenTabLeavesTheScreenAlone() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .horizontal))
    let third = store.addTab(to: ws) // nasconde `second` nella strip

    store.closeTab(second.id, in: ws) // tab viva ma non a schermo

    #expect(ws.visibleTabIDs == [first.id, third.id]) // schermo intatto
    #expect(ws.tabs.count == 2)
}

@Test func setSplitRatioRewritesTheLayout() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    store.splitFocusedPane(axis: .horizontal)
    guard case let .split(branchID, _, _, _, _) = ws.layout else {
        return #expect(Bool(false), "il workspace deve essere splittato")
    }

    store.setSplitRatio(0.7, forBranch: branchID, in: ws)

    guard case let .split(_, _, ratio, _, _) = ws.layout else {
        return #expect(Bool(false), "il layout deve restare uno split")
    }
    #expect(ratio == 0.7)
}

@Test func moveTabReordersWithinItsStripOnly() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = try #require(store.splitFocusedPane(axis: .horizontal))
    let third = store.addTab(to: ws) // strip B: [second, third]

    store.moveTab(third.id, before: second.id, in: ws)
    let paneB = try #require(ws.layout.pane(ws.focusedPaneID))
    #expect(paneB.tabIDs == [third.id, second.id])

    // Cross-pane: non è un riordino di strip, è un no-op (il drag fra pane è un lavoro futuro).
    store.moveTab(third.id, before: first.id, in: ws)
    #expect(ws.layout.pane(ws.focusedPaneID)?.tabIDs == [third.id, second.id])
}

// MARK: - Open in Split (sposta una tab esistente in un pane nuovo)

@Test func openInSplitMovesATabOutOfItsStrip() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let first = ws.tabs[0]
    let second = store.addTab(to: ws) // stessa strip: [first, second]

    #expect(store.openInSplit(second.id, axis: .horizontal, in: ws))

    #expect(ws.layout.paneIDs.count == 2)
    #expect(ws.visibleTabIDs == [first.id, second.id])
    #expect(ws.tabs.count == 2) // nessuna tab nuova: ha spostato quella che c'era
    #expect(ws.selectedTabID == second.id) // il nuovo pane prende il focus
}

@Test func openInSplitRefusesTheOnlyTabOfAPane() throws {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "relay")
    let second = try #require(store.splitFocusedPane(axis: .horizontal)) // sola nel suo pane

    // Dividerla accanto a sé stessa non produce niente.
    #expect(!store.openInSplit(second.id, axis: .vertical, in: ws))
    #expect(ws.layout.paneIDs.count == 2)
}

// MARK: - Visibilità: a schermo, non solo focused

@Test func completionOnAVisibleButUnfocusedPaneDoesNotBump() {
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

@Test func completionOnAHiddenStripTabStillBumpsAndNotifies() {
    let store = WorkspaceStore()
    let other = store.createWorkspace(name: "altro")
    let ws = store.createWorkspace(name: "relay")
    let hidden = ws.tabs[0]
    store.addTab(to: ws) // stessa strip: `hidden` esce dallo schermo
    #expect(!ws.isVisible(hidden.id))
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
    store.addTab(to: ws) // strip del secondo pane: [second, third]
    store.selectTab(second.id, in: ws) // visibile `second`, la terza nascosta

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())

    let workspace = restored.workspaces[0]
    #expect(workspace.visibleTabIDs == [first.id, second.id])
    #expect(workspace.selectedTabID == second.id)
    #expect(workspace.focusedPaneID == ws.focusedPaneID)
    #expect(workspace.layout == ws.layout)
    #expect(workspace.tabs.count == 3) // `third` è viva nella strip
}

@Test func restoreDropsPanesWhoseTabsAreGone() {
    // Snapshot con un pane le cui tab non esistono più (file editato a mano, corruzione parziale
    // che decodifica ancora): il pane orfano cade e il fratello prende il suo posto.
    let alive = TabSnapshot(id: UUID(), title: "t", hasCustomTitle: false, currentDirectory: nil)
    let root = SplitPane(tabIDs: [alive.id])
    let ghost = SplitPane(tabIDs: [UUID(), UUID()])
    let layout = SplitNode.pane(root)
        .splitting(root.id, axis: .horizontal, with: ghost, branchID: UUID())
    let ws = WorkspaceSnapshot(
        id: UUID(), name: "w", rootPath: nil, pinned: false,
        selectedTabID: alive.id, splitLayout: layout, focusedPaneID: ghost.id, tabs: [alive]
    )
    let store = WorkspaceStore()
    store.restore(from: LayoutSnapshot(selectedWorkspaceID: nil, workspaces: [ws]))

    let restored = store.workspaces[0]
    #expect(restored.layout.paneIDs == [root.id]) // il pane fantasma è caduto
    #expect(restored.selectedTabID == alive.id)
    #expect(restored.focusedPaneID == root.id) // il focus non resta appeso al fantasma
}

@Test func restoreAdoptsTabsLeftOutOfTheLayout() {
    // Snapshot v1 (foglie-tab): le tab che non stavano nel layout ("non montate" di allora) non
    // hanno un pane. Vengono adottate dal pane della selezione, in coda alla strip.
    let mounted = TabSnapshot(id: UUID(), title: "a", hasCustomTitle: false, currentDirectory: nil)
    let orphan = TabSnapshot(id: UUID(), title: "b", hasCustomTitle: false, currentDirectory: nil)
    let root = SplitPane(tabIDs: [mounted.id])
    let ws = WorkspaceSnapshot(
        id: UUID(), name: "w", rootPath: nil, pinned: false,
        selectedTabID: mounted.id, splitLayout: .pane(root), tabs: [mounted, orphan]
    )
    let store = WorkspaceStore()
    store.restore(from: LayoutSnapshot(selectedWorkspaceID: nil, workspaces: [ws]))

    let restored = store.workspaces[0]
    #expect(restored.layout.pane(root.id)?.tabIDs == [mounted.id, orphan.id])
    #expect(restored.selectedTabID == mounted.id) // l'adozione non ruba la selezione
}

@Test func layoutsSavedBeforeSplitDecodeAsSinglePane() throws {
    // Campo additivo: un `WorkspaceSnapshot` senza `splitLayout` né `focusedPaneID` deve
    // decodificare, non far fallire l'intero layout dell'utente.
    let json = """
    {"id":"\(UUID().uuidString)","name":"w","rootPath":null,"pinned":false,
     "selectedTabID":null,"tabs":[]}
    """
    let decoded = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(json.utf8))

    #expect(decoded.splitLayout == nil)
    #expect(decoded.focusedPaneID == nil)
}
