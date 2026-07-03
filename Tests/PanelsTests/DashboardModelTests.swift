import AgentProtocol
import Foundation
@testable import Panels
import Testing
import WorkspaceModel

// Logica pura della dashboard: quali tab sono sessioni, ordinamento per urgenza, filtro, età.

private func workspace(_ name: String, tabs: [Tab]) -> Workspace {
    Workspace(name: name, tabs: tabs)
}

@Test func onlyAgentSessionsAreListed() {
    let bare = Tab() // shell nuda: fuori
    let live = Tab(agentState: .running)
    let endedPending = Tab(agentState: .unknown, attention: .pending) // sessione finita, sospesa
    let resumable = Tab(resume: ResumeBinding(agent: "claude", sessionId: "s1", label: "x"))
    let items = DashboardModel.items(
        workspaces: [workspace("w", tabs: [bare, live, endedPending, resumable])]
    )
    // L'ordine esatto lo verifica il test di ordinamento; qui conta l'insieme.
    #expect(Set(items.map(\.tab.id)) == Set([live.id, endedPending.id, resumable.id]))
}

/// Triage: ciò che aspetta te (input, errore, completamenti) sopra ciò che lavora da solo.
@Test func itemsSortByUrgency() {
    let idle = Tab(agentState: .idle)
    let running = Tab(agentState: .running)
    let pending = Tab(agentState: .idle, attention: .pending)
    let unseen = Tab(agentState: .idle, attention: .unseen)
    let error = Tab(agentState: .error)
    let needsInput = Tab(agentState: .needsInput)
    let items = DashboardModel.items(
        workspaces: [workspace("w", tabs: [idle, running, pending, unseen, error, needsInput])]
    )
    #expect(items.map(\.tab.id) == [
        needsInput.id, error.id, unseen.id, pending.id, running.id, idle.id,
    ])
}

/// A pari urgenza vince l'evento più recente; senza timestamp si resta in fondo, in ordine
/// visivo stabile.
@Test func sameUrgencyPrefersRecent() {
    let older = Tab(agentState: .running, lastEventAt: Date(timeIntervalSince1970: 10))
    let newer = Tab(agentState: .running, lastEventAt: Date(timeIntervalSince1970: 99))
    let dateless = Tab(agentState: .running)
    let items = DashboardModel.items(
        workspaces: [workspace("w", tabs: [dateless, older, newer])]
    )
    #expect(items.map(\.tab.id) == [newer.id, older.id, dateless.id])
}

@Test func queryFiltersTitleWorkspaceAndCwd() {
    let api = Tab(title: "api-refactor", agentState: .running)
    let docs = Tab(
        title: "docs",
        currentDirectory: "/Users/x/projects/relay",
        agentState: .running
    )
    let other = Tab(title: "scratch", agentState: .running)
    let workspaces = [
        workspace("backend", tabs: [api]),
        workspace("frontend", tabs: [docs, other]),
    ]

    #expect(DashboardModel.items(workspaces: workspaces, query: "API").map(\.tab.id) == [api.id])
    #expect(DashboardModel.items(workspaces: workspaces, query: "backend")
        .map(\.tab.id) == [api.id])
    #expect(DashboardModel.items(workspaces: workspaces, query: "relay")
        .map(\.tab.id) == [docs.id])
    #expect(DashboardModel.items(workspaces: workspaces, query: "zzz").isEmpty)
}

@Test func ageFormatsCompactly() {
    let now = Date(timeIntervalSince1970: 100_000)
    #expect(DashboardModel.age(of: nil, now: now) == nil)
    #expect(DashboardModel.age(of: now.addingTimeInterval(-5), now: now) == "now")
    #expect(DashboardModel.age(of: now.addingTimeInterval(-45), now: now) == "45s")
    #expect(DashboardModel.age(of: now.addingTimeInterval(-180), now: now) == "3m")
    #expect(DashboardModel.age(of: now.addingTimeInterval(-7200), now: now) == "2h")
    #expect(DashboardModel.age(of: now.addingTimeInterval(-200_000), now: now) == "2d")
}

@Test func chipColorIsStableAndInAnsiRange() {
    let id = UUID()
    let first = DashboardModel.chipColorIndex(id)
    #expect(first == DashboardModel.chipColorIndex(id)) // stabile
    #expect((1 ... 6).contains(first)) // red..cyan della palette ANSI
}
