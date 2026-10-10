import AgentProtocol
import Foundation
@testable import Panels
import Testing
import WorkspaceModel

// Regole di triage condivise da Home e Projects.

@Test func onlyAgentSessionsCount() {
    #expect(!SessionTriage.isSession(Tab())) // shell nuda
    #expect(SessionTriage.isSession(Tab(agentState: .running)))
    #expect(SessionTriage.isSession(Tab(agentState: .unknown, attention: .pending)))
    #expect(SessionTriage.isSession(
        Tab(resume: ResumeBinding(agent: "claude", sessionId: "s1", label: "x"))
    ))
}

/// Ciò che aspetta te (input, errore, completamenti) sopra ciò che lavora da solo.
@Test func urgencyPutsWhatWaitsForYouFirst() {
    let ranks = [
        Tab(agentState: .needsInput), Tab(agentState: .error),
        Tab(agentState: .idle, attention: .unseen), Tab(agentState: .idle, attention: .pending),
        Tab(agentState: .running), Tab(agentState: .idle),
    ].map(SessionTriage.urgencyRank)
    #expect(ranks == ranks.sorted(by: >))
    #expect(Set(ranks).count == ranks.count)
}

@Test func ageFormatsCompactly() {
    let now = Date(timeIntervalSince1970: 100_000)
    #expect(SessionTriage.age(of: nil, now: now) == nil)
    #expect(SessionTriage.age(of: now.addingTimeInterval(-5), now: now) == "now")
    #expect(SessionTriage.age(of: now.addingTimeInterval(-45), now: now) == "45s")
    #expect(SessionTriage.age(of: now.addingTimeInterval(-180), now: now) == "3m")
    #expect(SessionTriage.age(of: now.addingTimeInterval(-7200), now: now) == "2h")
    #expect(SessionTriage.age(of: now.addingTimeInterval(-200_000), now: now) == "2d")
}
