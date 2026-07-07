@testable import AgentProtocol
import Foundation
import Testing

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
        runId: "run-1",
        state: .needsInput,
        source: .hook,
        confidence: 1,
        timestamp: Date(timeIntervalSince1970: 1000)
    )
    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(AgentStateEvent.self, from: data)
    #expect(decoded == event)
    #expect(decoded.runId == "run-1")
}

@Test func decoderToleratesEventWithoutRunId() throws {
    // Evento da un CLI più vecchio: nessuna chiave `runId`, decode valido con runId nil.
    let line = """
    {"agent":"claude","sessionId":"abc","paneId":"p","state":"idle","source":"hook",\
    "confidence":1,"timestamp":1000}
    """
    let event = try JSONDecoder().decode(AgentStateEvent.self, from: Data(line.utf8))
    #expect(event.runId == nil)
    #expect(event.state == .idle)
}

@Test func eventTypeRawValues() {
    #expect(AgentEventType.state.rawValue == "agent.state")
    #expect(AgentEventType.sessionStart.rawValue == "agent.session.start")
}
