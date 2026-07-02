import AgentProtocol
@testable import Panels
import Testing
import WorkspaceModel

private func tab(_ state: AgentState, attention: Bool = false) -> Tab {
    Tab(agentState: state, attention: attention)
}

/// Il badge di running/needs_input/error deriva dallo STATO: resta finché lo stato cambia,
/// indipendentemente da `attention` (needs_input non si spegne al focus).
@Test func runningShowsRunningRegardlessOfAttention() {
    #expect(BadgeKind.forTab(tab(.running, attention: false)) == .running)
    #expect(BadgeKind.forTab(tab(.running, attention: true)) == .running)
}

@Test func needsInputPersistsRegardlessOfAttention() {
    #expect(BadgeKind.forTab(tab(.needsInput, attention: false)) == .needsInput)
    #expect(BadgeKind.forTab(tab(.needsInput, attention: true)) == .needsInput)
}

@Test func errorPersistsRegardlessOfAttention() {
    #expect(BadgeKind.forTab(tab(.error, attention: false)) == .error)
}

/// "completato" è transitorio: solo idle + attention -> check; idle senza attention -> niente.
@Test func completedNeedsAttention() {
    #expect(BadgeKind.forTab(tab(.idle, attention: true)) == .completed)
    #expect(BadgeKind.forTab(tab(.idle, attention: false)) == .none)
}

@Test func unknownShowsNothing() {
    #expect(BadgeKind.forTab(tab(.unknown)) == .none)
}

@Test func workspaceAggregatesMostSevere() {
    let workspace = Workspace(name: "w", tabs: [tab(.running), tab(.needsInput), tab(.idle)])
    #expect(BadgeKind.forWorkspace(workspace) == .needsInput)
}

@Test func workspaceRunningBeatsCompleted() {
    let workspace = Workspace(name: "w", tabs: [tab(.running), tab(.idle, attention: true)])
    #expect(BadgeKind.forWorkspace(workspace) == .running)
}
