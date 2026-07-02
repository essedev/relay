import Foundation
import Testing

@testable import AgentProtocol

@Test func agentStateRawValues() {
    #expect(AgentState.needsInput.rawValue == "needs_input")
    #expect(AgentState(rawValue: "running") == .running)
    #expect(AgentState.allCases.count == 5)
}

@Test func agentStateEventCodableRoundtrip() throws {
    let event = AgentStateEvent(
        agent: "claude",
        sessionId: "abc",
        paneId: "pane-1",
        state: .needsInput,
        source: .hook,
        confidence: 1,
        timestamp: Date(timeIntervalSince1970: 1000)
    )
    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(AgentStateEvent.self, from: data)
    #expect(decoded == event)
}

@Test func eventTypeRawValues() {
    #expect(AgentEventType.state.rawValue == "agent.state")
    #expect(AgentEventType.sessionStart.rawValue == "agent.session.start")
}
