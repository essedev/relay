import AgentProtocol
import Foundation
@testable import Panels
import Testing
import WorkspaceModel

// Logica pura di Home (triage dei progetti aperti) e Projects (catalogo per gruppo).

private let now = Date(timeIntervalSince1970: 1_000_000)

private func project(
    _ name: String, closed: Bool = false, group: UUID? = nil, lastActive: Date? = nil,
    path: String? = nil, tabs: [Tab] = [Tab()]
) -> Workspace {
    Workspace(
        name: name, rootPath: path, closed: closed, groupID: group, lastActiveAt: lastActive,
        tabs: tabs
    )
}

// MARK: - Home

@Test func needsYouListsOnlyOpenProjectsInTriageOrder() {
    let unseen = Tab(agentState: .idle, attention: .unseen, lastEventAt: now)
    let input = Tab(agentState: .needsInput, lastEventAt: now.addingTimeInterval(-60))
    let error = Tab(agentState: .error, lastEventAt: now)
    let closedInput = Tab(agentState: .needsInput)
    let entries = HomeModel.needsYou([
        project("a", tabs: [unseen]),
        project("b", tabs: [input, Tab(agentState: .running)]),
        project("c", tabs: [error]),
        project("d", closed: true, tabs: [closedInput]),
    ])
    // Input prima dell'errore, errore prima del completamento; il chiuso non c'è.
    #expect(entries.map(\.tab.id) == [input.id, error.id, unseen.id])
}

@Test func workingListsRunningSessionsOfOpenProjects() {
    let running = Tab(agentState: .running)
    let entries = HomeModel.working([
        project("a", tabs: [running, Tab(agentState: .idle)]),
        project("b", closed: true, tabs: [Tab(agentState: .running)]),
    ])
    #expect(entries.map(\.tab.id) == [running.id])
}

@Test func quietProposesOnlyStillOpenProjectsWithAKnownPast() {
    let old = now.addingTimeInterval(-(HomeModel.quietAfter + 60))
    let still = project("still", lastActive: old)
    let busy = project("busy", lastActive: old, tabs: [Tab(agentState: .needsInput)])
    let recent = project("recent", lastActive: now.addingTimeInterval(-60))
    let unknown = project("unknown")
    let closed = project("closed", closed: true, lastActive: old)
    let quiet = HomeModel.quiet([still, busy, recent, unknown, closed], now: now)
    #expect(quiet.map(\.name) == ["still"])
}

@Test func recentlyClosedComesNewestFirst() {
    let list = HomeModel.recentlyClosed([
        project("older", closed: true, lastActive: now.addingTimeInterval(-500)),
        project("open", lastActive: now),
        project("never", closed: true),
        project("newer", closed: true, lastActive: now.addingTimeInterval(-10)),
    ])
    #expect(list.map(\.name) == ["newer", "older", "never"])
}

@Test func theHeadlineSaysTheSituation() {
    #expect(HomeModel.headline(needing: 0) == "Nothing needs you")
    #expect(HomeModel.headline(needing: 1) == "1 session needs you")
    #expect(HomeModel.headline(needing: 3) == "3 sessions need you")
}

// MARK: - Projects

@Test func sectionsFollowTheGroupsThenTheLooseProjects() {
    let work = WorkspaceGroup(name: "P1", colorIndex: 1)
    let side = WorkspaceGroup(name: "P2", colorIndex: 3)
    let sections = ProjectsModel.sections(
        workspaces: [
            project("loose"),
            project("w1", group: work.id),
            project("orphan", group: UUID()), // gruppo inesistente: degrada a libero
        ],
        groups: [work, side]
    )
    // P2 non ha progetti: sparisce.
    #expect(sections.map(\.group?.name) == ["P1", nil])
    #expect(sections[1].projects.map(\.name) == ["loose", "orphan"])
}

@Test func openProjectsLeadThenTheMostRecent() {
    let sections = ProjectsModel.sections(
        workspaces: [
            project("closed-new", closed: true, lastActive: now),
            project("open-old", lastActive: now.addingTimeInterval(-900)),
            project("closed-old", closed: true, lastActive: now.addingTimeInterval(-500)),
            project("open-new", lastActive: now.addingTimeInterval(-10)),
        ],
        groups: []
    )
    #expect(sections[0].projects.map(\.name) == [
        "open-new",
        "open-old",
        "closed-new",
        "closed-old",
    ])
}

@Test func theFilterAndTheQueryNarrowTheCatalog() {
    let all = [
        project("Zeno", path: "~/Projects/zeno"),
        project("Engine", closed: true, path: "~/Projects/zeno-engine"),
        project("Other", closed: true, path: "~/Projects/other"),
    ]
    let byPath = ProjectsModel.sections(workspaces: all, groups: [], query: "ZENO")
    #expect(byPath.flatMap(\.projects).map(\.name) == ["Zeno", "Engine"])
    let closedOnly = ProjectsModel.sections(
        workspaces: all, groups: [], query: "zeno", filter: .closed
    )
    #expect(closedOnly.flatMap(\.projects).map(\.name) == ["Engine"])
}
