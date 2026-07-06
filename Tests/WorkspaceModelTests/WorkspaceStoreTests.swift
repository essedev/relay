import AgentProtocol
import Foundation
import Testing
@testable import WorkspaceModel

@Test func createWorkspaceSelectsItWithOneTab() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "api")

    #expect(store.workspaces.count == 1)
    #expect(store.selectedWorkspaceID == ws.id)
    #expect(ws.tabs.count == 1)
    #expect(ws.selectedTabID == ws.tabs.first?.id)
}

@Test func addTabSelectsNewTab() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "api")
    let tab = store.addTab(to: ws)

    #expect(ws.tabs.count == 2)
    #expect(ws.selectedTabID == tab.id)
}

@Test func addTabInheritsCurrentDirectoryFromSelectedTab() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "api")
    ws.tabs[0].currentDirectory = "/Users/doppia/dev/relay"

    let tab = store.addTab(to: ws)
    #expect(tab.currentDirectory == "/Users/doppia/dev/relay")

    // Senza cwd nota, la nuova tab non ne inventa una (fallback al rootPath a runtime).
    let bare = store.createWorkspace(name: "other")
    let bareTab = store.addTab(to: bare)
    #expect(bareTab.currentDirectory == nil)
}

@Test func closeSelectedTabSelectsNeighbor() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "api")
    let first = ws.tabs[0]
    let second = store.addTab(to: ws)
    store.selectTab(second.id, in: ws)

    let removed = store.closeTab(second.id, in: ws)

    #expect(removed == second.id)
    #expect(ws.tabs.count == 1)
    #expect(ws.selectedTabID == first.id)
}

@Test func closingLastTabClosesWorkspace() {
    let store = WorkspaceStore()
    let first = store.createWorkspace(name: "a")
    let second = store.createWorkspace(name: "b") // una sola tab
    let onlyTab = second.tabs[0]

    let removed = store.closeTab(onlyTab.id, in: second)

    #expect(removed == onlyTab.id)
    #expect(store.workspaces.map(\.id) == [first.id]) // il workspace vuoto è sparito
    #expect(store.selectedWorkspaceID == first.id)
}

@Test func moveWorkspaceBeforeTargetInserts() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")

    // c prima di a: c va in testa, a e b scorrono.
    store.moveWorkspace(c.id, before: a.id)
    #expect(store.workspaces.map(\.id) == [c.id, a.id, b.id])

    // target nil: in fondo.
    store.moveWorkspace(c.id, before: nil)
    #expect(store.workspaces.map(\.id) == [a.id, b.id, c.id])

    // id uguale al target: no-op (non si sposta prima di sé stesso).
    store.moveWorkspace(a.id, before: a.id)
    #expect(store.workspaces.map(\.id) == [a.id, b.id, c.id])
}

@Test func moveWorkspaceAfterTargetInserts() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")

    // a dopo c: in fondo.
    store.moveWorkspace(a.id, after: c.id)
    #expect(store.workspaces.map(\.id) == [b.id, c.id, a.id])

    // b dopo a (ora ultimo): subito dopo a.
    store.moveWorkspace(b.id, after: a.id)
    #expect(store.workspaces.map(\.id) == [c.id, a.id, b.id])

    // dopo sé stesso: no-op.
    store.moveWorkspace(c.id, after: c.id)
    #expect(store.workspaces.map(\.id) == [c.id, a.id, b.id])
}

/// Rilascio in fondo al segmento pinned (non l'ultimo segmento): `after` sposta davvero, dove
/// `before` col primo del segmento successivo sarebbe stato un no-op. Scenario del bug: canonico
/// [a, b, c] con b, c pinned (visivo [b, c, a]); trascinando b dopo c l'ordine visivo dei pinned
/// diventa [c, b].
@Test func dropAtEndOfPinnedSegmentReorders() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")
    store.togglePin(b.id)
    store.togglePin(c.id)
    #expect(store.orderedWorkspaces.map(\.id) == [b.id, c.id, a.id])

    store.moveWorkspace(b.id, after: c.id)
    #expect(store.orderedWorkspaces.map(\.id) == [c.id, b.id, a.id])
}

@Test func restoreSanitizesDanglingSelectedTabID() {
    // Snapshot con selectedTabID che non è tra le tab del workspace (file editato a mano,
    // corruzione parziale): il restore deve ripiegare sulla prima tab, non lasciare la selezione
    // appesa a un id inesistente.
    let realTab = TabSnapshot(id: UUID(), title: "t", hasCustomTitle: false, currentDirectory: nil)
    let ws = WorkspaceSnapshot(
        id: UUID(), name: "w", rootPath: nil, pinned: false,
        selectedTabID: UUID(), tabs: [realTab]
    )
    let store = WorkspaceStore()
    store.restore(from: LayoutSnapshot(selectedWorkspaceID: nil, workspaces: [ws]))

    let restored = store.workspaces[0]
    #expect(restored.selectedTabID == realTab.id)
    #expect(restored.selectedTab != nil)
}

@Test func moveTabBeforeTargetInserts() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "ws")
    let t1 = ws.tabs[0]
    let t2 = store.addTab(to: ws)
    let t3 = store.addTab(to: ws)
    store.selectTab(t2.id, in: ws)

    // t3 prima di t1: ordine [t3, t1, t2], selezione invariata (t2).
    store.moveTab(t3.id, before: t1.id, in: ws)
    #expect(ws.tabs.map(\.id) == [t3.id, t1.id, t2.id])
    #expect(ws.selectedTabID == t2.id)

    // target nil: in fondo.
    store.moveTab(t3.id, before: nil, in: ws)
    #expect(ws.tabs.map(\.id) == [t1.id, t2.id, t3.id])
}

@Test func closeWorkspaceReturnsTabIDsAndSelectsNeighbor() {
    let store = WorkspaceStore()
    let first = store.createWorkspace(name: "a")
    let second = store.createWorkspace(name: "b")
    let extraTab = store.addTab(to: second)

    let removed = store.closeWorkspace(second.id)

    #expect(Set(removed).contains(extraTab.id))
    #expect(removed.count == 2)
    #expect(store.workspaces.count == 1)
    #expect(store.selectedWorkspaceID == first.id)
}

@Test func togglePinPartitionsWorkspaces() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    _ = store.createWorkspace(name: "b")

    store.togglePin(a.id)

    #expect(store.pinnedWorkspaces.map(\.id) == [a.id])
    #expect(store.otherWorkspaces.count == 1)
}

@Test func renameWorkspaceIgnoresEmpty() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "api")

    store.renameWorkspace(ws.id, to: "  backend  ")
    #expect(ws.name == "backend") // trim

    store.renameWorkspace(ws.id, to: "   ")
    #expect(ws.name == "backend") // vuoto ignorato
}

@Test func orderedWorkspacesFloatsAttentionUnderPinned() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    let c = store.createWorkspace(name: "c")

    // c pinnato; b chiede input -> ordine atteso: [c (pinned), b (attenzione), a (calmo)].
    store.togglePin(c.id)
    b.tabs[0].agentState = .needsInput

    #expect(store.orderedWorkspaces.map(\.id) == [c.id, b.id, a.id])

    // "completato non visto" (unseen) galleggia come needs_input.
    b.tabs[0].agentState = .idle
    a.tabs[0].attention = .unseen
    #expect(store.orderedWorkspaces.map(\.id) == [c.id, a.id, b.id])

    // Il sospeso (pending) NON galleggia: segnale quieto, l'ordine resta quello canonico.
    a.tabs[0].attention = .pending
    #expect(store.orderedWorkspaces.map(\.id) == [c.id, a.id, b.id])
}

@Test func pendingDoesNotFloatWorkspaces() {
    let store = WorkspaceStore()
    store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    b.tabs[0].attention = .pending
    // b in sospeso ma niente float: solo l'attenzione fresca riordina la sidebar.
    #expect(store.orderedWorkspaces.map(\.name) == ["a", "b"])
}

@Test func renameTabSetsCustomTitle() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "a")
    let tab = ws.tabs[0]

    store.renameTab(tab.id, in: ws, to: "server")

    #expect(tab.title == "server")
    #expect(tab.hasCustomTitle)

    store.renameTab(tab.id, in: ws, to: "   ")
    #expect(tab.title == "server") // vuoto ignorato
}

@Test func snapshotRestoreRoundTrips() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    store.renameTab(a.tabs[0].id, in: a, to: "shell")
    a.tabs[0].currentDirectory = "/tmp/x"
    let b = store.createWorkspace(name: "b")
    store.addTab(to: b)
    store.togglePin(b.id)
    store.selectWorkspace(a.id)

    let snap = store.snapshot()
    let restored = WorkspaceStore()
    restored.restore(from: snap)

    // struttura identica: id, nomi, cwd, pin, ordine, selezione
    #expect(restored.snapshot() == snap)
    #expect(restored.selectedWorkspaceID == a.id)
    #expect(restored.workspaces.map(\.name) == ["a", "b"])
    #expect(restored.workspaces[1].pinned)
    #expect(restored.workspaces[0].tabs[0].hasCustomTitle)
    // Lo stato agente non è persistito: la tab rinasce `unknown`.
    #expect(restored.workspaces[0].tabs[0].agentState == .unknown)
}

@Test func applyAgentStateCapturesAndClearsResume() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "a")
    let tab = ws.tabs[0]
    store.renameTab(tab.id, in: ws, to: "chat")

    store.applyAgentState(
        paneId: tab.id.uuidString,
        agent: "claude",
        sessionId: "s-1",
        state: .running,
        at: Date()
    )
    #expect(tab.resume == ResumeBinding(agent: "claude", sessionId: "s-1", label: "chat"))
    #expect(!tab.pendingResume) // sessione viva (running), non pending

    // SessionEnd -> unknown azzera il binding.
    store.applyAgentState(paneId: tab.id.uuidString, sessionId: "s-1", state: .unknown, at: Date())
    #expect(tab.resume == nil)
}

@Test func emptySessionIdDoesNotBind() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "a")
    let tab = ws.tabs[0]

    store.applyAgentState(paneId: tab.id.uuidString, state: .running, at: Date())
    #expect(tab.resume == nil) // niente sessionId -> niente binding
}

@Test func pendingResumeSurvivesRestore() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "a")
    let binding = ResumeBinding(agent: "claude", sessionId: "s-1", label: "chat")
    ws.tabs[0].resume = binding
    // agentState riparte `unknown` di default -> pending.
    #expect(ws.tabs[0].pendingResume)

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())
    #expect(restored.workspaces[0].tabs[0].resume == binding)
    #expect(restored.workspaces[0].tabs[0].pendingResume)
}

@Test func restoreValidatesSelectionFallback() {
    let store = WorkspaceStore()
    let ws = WorkspaceSnapshot(
        id: UUID(),
        name: "x",
        rootPath: nil,
        pinned: false,
        selectedTabID: nil,
        tabs: []
    )
    let snap = LayoutSnapshot(selectedWorkspaceID: UUID(),
                              workspaces: [ws]) // selezione inesistente

    store.restore(from: snap)

    #expect(store.selectedWorkspaceID == store.workspaces.first?.id) // fallback al primo
}

// MARK: - Archive

@Test func archiveExcludesFromListDePinsAndMovesSelection() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    store.togglePin(b.id)
    store.selectWorkspace(b.id)

    store.setArchived(b.id, true)

    #expect(b.archived)
    #expect(!b.pinned) // archiviare de-pinna (mutuamente esclusivi)
    #expect(store.orderedWorkspaces.map(\.id) == [a.id]) // fuori dalla lista principale
    #expect(store.archivedWorkspaces.map(\.id) == [b.id])
    #expect(store.selectedWorkspaceID == a.id) // la selezione lascia l'archiviato
}

@Test func unarchiveRestoresToListWithoutChangingSelection() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    store.setArchived(b.id, true)
    store.selectWorkspace(a.id)

    store.toggleArchive(b.id) // ripristina

    #expect(!b.archived)
    #expect(store.orderedWorkspaces.contains { $0.id == b.id })
    #expect(store.archivedWorkspaces.isEmpty)
    #expect(store.selectedWorkspaceID == a.id) // il ripristino non ruba la selezione
}

@Test func cannotArchiveLastVisibleWorkspace() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    store.setArchived(b.id, true)

    store.setArchived(a.id, true) // a è l'unico rimasto visibile: no-op

    #expect(!a.archived)
    #expect(store.orderedWorkspaces.map(\.id) == [a.id])
}

@Test func archivedSurvivesSnapshotRoundTrip() {
    let store = WorkspaceStore()
    let a = store.createWorkspace(name: "a")
    let b = store.createWorkspace(name: "b")
    store.setArchived(b.id, true)

    let restored = WorkspaceStore()
    restored.restore(from: store.snapshot())

    #expect(restored.archivedWorkspaces.map(\.name) == ["b"])
    #expect(restored.orderedWorkspaces.map(\.name) == ["a"])
    #expect(restored.selectedWorkspaceID == a.id) // non seleziona un archiviato al restore
}

@Test func workspaceSnapshotDecodesWithoutArchivedField() throws {
    // Layout salvato prima della feature: nessun campo `archived`. Deve decodificare a `false`,
    // non far fallire l'intero decode (= layout dell'utente buttato via).
    let json = "{\"id\":\"\(UUID().uuidString)\",\"name\":\"old\",\"pinned\":false,\"tabs\":[]}"
    let snap = try JSONDecoder().decode(WorkspaceSnapshot.self, from: Data(json.utf8))
    #expect(!snap.archived)
    #expect(snap.name == "old")
}
