import AgentProtocol
import Testing

@testable import WorkspaceModel

@Test func severityOrder() {
    #expect(AgentSeverity.rank(.needsInput) > AgentSeverity.rank(.error))
    #expect(AgentSeverity.rank(.error) > AgentSeverity.rank(.running))
    #expect(AgentSeverity.rank(.running) > AgentSeverity.rank(.idle))
    #expect(AgentSeverity.rank(.idle) > AgentSeverity.rank(.unknown))
}

@Test(arguments: [
    ([AgentState.idle, .running, .needsInput, .error], AgentState.needsInput),
    ([.idle, .running, .error], .error),
    ([.idle, .running], .running),
    ([.idle], .idle),
    ([], .unknown),
])
func aggregatePicksMostSevere(states: [AgentState], expected: AgentState) {
    #expect(AgentSeverity.aggregate(states) == expected)
}
