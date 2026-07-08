import AgentProtocol
@testable import Panels
import Testing
import WorkspaceModel

private func tab(_ state: AgentState, attention: AttentionLevel = .none) -> Tab {
    Tab(agentState: state, attention: attention)
}

/// Il badge di running/needs_input/error deriva dallo STATO: resta finché lo stato cambia,
/// indipendentemente da `attention` (needs_input non si spegne al focus).
@Test func runningShowsRunningRegardlessOfAttention() {
    #expect(BadgeKind.forTab(tab(.running, attention: .none)) == .running)
    #expect(BadgeKind.forTab(tab(.running, attention: .unseen)) == .running)
}

@Test func needsInputPersistsRegardlessOfAttention() {
    #expect(BadgeKind.forTab(tab(.needsInput, attention: .none)) == .needsInput)
    #expect(BadgeKind.forTab(tab(.needsInput, attention: .unseen)) == .needsInput)
}

@Test func errorPersistsRegardlessOfAttention() {
    #expect(BadgeKind.forTab(tab(.error, attention: .none)) == .error)
}

/// Il completamento segue il livello di attenzione: `unseen` = badge pieno (forte), `pending` =
/// punto dimesso (sospeso), `none` = niente.
@Test func completedFollowsAttentionLevel() {
    #expect(BadgeKind.forTab(tab(.idle, attention: .unseen)) == .completed)
    #expect(BadgeKind.forTab(tab(.idle, attention: .pending)) == .pending)
    #expect(BadgeKind.forTab(tab(.idle, attention: .none)) == .none)
}

/// Il sospeso sopravvive alla fine della sessione: a stato `unknown` il badge resta.
@Test func attentionSurvivesSessionEnd() {
    #expect(BadgeKind.forTab(tab(.unknown, attention: .pending)) == .pending)
    #expect(BadgeKind.forTab(tab(.unknown, attention: .unseen)) == .completed)
    #expect(BadgeKind.forTab(tab(.unknown)) == .none)
}

@Test func workspaceAggregatesMostSevere() {
    let workspace = Workspace(name: "w", tabs: [tab(.running), tab(.needsInput), tab(.idle)])
    #expect(WorkspaceBadgeInfo.forWorkspace(workspace).kind == .needsInput)
}

@Test func workspaceRunningBeatsCompleted() {
    let workspace = Workspace(name: "w", tabs: [tab(.running), tab(.idle, attention: .unseen)])
    #expect(WorkspaceBadgeInfo.forWorkspace(workspace).kind == .running)
}

/// Il punto quieto del sospeso è il segnale meno severo: qualunque altro lo copre.
@Test func workspacePendingIsQuietest() {
    let alone = Workspace(name: "w", tabs: [tab(.idle, attention: .pending), tab(.idle)])
    #expect(WorkspaceBadgeInfo.forWorkspace(alone).kind == .pending)

    let withCompleted = Workspace(
        name: "w",
        tabs: [tab(.idle, attention: .pending), tab(.idle, attention: .unseen)]
    )
    #expect(WorkspaceBadgeInfo.forWorkspace(withCompleted).kind == .completed)
}

/// Il contatore conta solo le tab nello stato più severo, non tutti gli agenti attivi.
@Test func workspaceBadgeCountsOnlyTopState() {
    let workspace = Workspace(
        name: "w",
        tabs: [tab(.needsInput), tab(.needsInput), tab(.running), tab(.idle)]
    )
    let info = WorkspaceBadgeInfo.forWorkspace(workspace)
    #expect(info == WorkspaceBadgeInfo(kind: .needsInput, count: 2))
}

@Test func workspaceBadgeSingleAndEmpty() {
    let single = Workspace(name: "w", tabs: [tab(.running)])
    #expect(WorkspaceBadgeInfo.forWorkspace(single) == WorkspaceBadgeInfo(kind: .running, count: 1))

    let quiet = Workspace(name: "w", tabs: [tab(.idle), tab(.unknown)])
    #expect(WorkspaceBadgeInfo.forWorkspace(quiet) == WorkspaceBadgeInfo(kind: .none, count: 0))
}
