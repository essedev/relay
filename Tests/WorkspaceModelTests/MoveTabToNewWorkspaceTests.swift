import Foundation
import Testing
@testable import WorkspaceModel

@Test func moveTabToNewWorkspaceMovesSameTabObject() {
    let store = WorkspaceStore()
    let src = store.createWorkspace(name: "src")
    let stayer = src.tabs[0]
    let mover = store.addTab(to: src)
    mover.currentDirectory = "/tmp/work"
    store.selectTab(stayer.id, in: src)

    let dst = store.moveTabToNewWorkspace(mover.id, from: src, name: "Workspace 2")

    // Il nuovo workspace nasce con la tab spostata (stesso oggetto/id) attiva ed è il selezionato.
    #expect(dst != nil)
    #expect(dst?.tabs.map(\.id) == [mover.id])
    #expect(dst?.tabs.first === mover) // stesso oggetto: la surface (chiavata per id) resta intatta
    #expect(dst?.selectedTabID == mover.id)
    #expect(store.selectedWorkspaceID == dst?.id)
    #expect(dst?.nameOrigin == .default)
    #expect(dst?.rootPath == "/tmp/work") // eredita la cwd della tab
    // L'origine perde solo la tab spostata e riseleziona un vicino.
    #expect(src.tabs.map(\.id) == [stayer.id])
    #expect(src.selectedTabID == stayer.id)
    #expect(store.workspaces.map(\.id) == [src.id, dst?.id])
}

@Test func moveTabToNewWorkspaceNoOpForOnlyTab() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "solo")
    let onlyTab = ws.tabs[0]

    // Spostare l'unica tab svuoterebbe l'origine: no-op (niente nuovo workspace).
    let result = store.moveTabToNewWorkspace(onlyTab.id, from: ws, name: "Workspace 2")

    #expect(result == nil)
    #expect(store.workspaces.map(\.id) == [ws.id])
    #expect(ws.tabs.map(\.id) == [onlyTab.id])
}

@Test func moveTabToNewWorkspaceNoOpForUnknownTab() {
    let store = WorkspaceStore()
    let ws = store.createWorkspace(name: "ws")
    store.addTab(to: ws)

    let result = store.moveTabToNewWorkspace(UUID(), from: ws, name: "Workspace 2")

    #expect(result == nil)
    #expect(store.workspaces.count == 1)
}
