import Foundation
@testable import WorkspaceModel

/// Fixture condivisa dei test di `applyAgentState`: uno store con due workspace, il primo (A)
/// selezionato quindi "visibile", il secondo (B) nascosto. Usata da `AgentApplyTests` e
/// `AgentEventGuardTests` (split per il budget di dimensione file, stessa base).
struct AgentFixture {
    let store: WorkspaceStore
    let visibleTab: Tab
    let hiddenTab: Tab
}

@MainActor
func makeAgentFixture() -> AgentFixture {
    let store = WorkspaceStore()
    let visible = store.createWorkspace(name: "A")
    let hidden = store.createWorkspace(name: "B")
    // L'ultima creata resta selezionata: rendo esplicito che "A" è la visibile.
    store.selectWorkspace(visible.id)
    return AgentFixture(store: store, visibleTab: visible.tabs[0], hiddenTab: hidden.tabs[0])
}
