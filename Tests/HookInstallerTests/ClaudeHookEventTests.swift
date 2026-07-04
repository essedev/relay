import AgentProtocol
import Foundation
import HookInstaller
import Testing

// Path stdin -> evento del CLI hook, ora puro e testabile (era zero-coverage nell'eseguibile).

private let epoch = Date(timeIntervalSince1970: 1000)

@Test func compactSessionStartProducesNoEvent() {
    // Auto-compact a metà turno: soppresso, altrimenti fingerebbe un completamento.
    let event = ClaudeHookEvent.make(
        requested: .idle,
        payload: ["hook_event_name": "SessionStart", "source": "compact"],
        env: [:],
        now: epoch
    )
    #expect(event == nil)
}

@Test func sessionIdComesFromPayloadThenEnv() {
    let fromPayload = ClaudeHookEvent.make(
        requested: .running,
        payload: ["session_id": "abc"],
        env: ["CLAUDE_SESSION_ID": "xyz"],
        now: epoch
    )
    #expect(fromPayload?.sessionId == "abc") // il payload vince

    let fromEnv = ClaudeHookEvent.make(
        requested: .running,
        payload: nil,
        env: ["CLAUDE_SESSION_ID": "xyz"],
        now: epoch
    )
    #expect(fromEnv?.sessionId == "xyz")
}

@Test func unknownSessionIdIsEmptyNotPaneId() {
    // Nessun session_id: sessionId vuoto (niente resume binding), paneId comunque dall'env.
    let event = ClaudeHookEvent.make(
        requested: .running,
        payload: nil,
        env: ["RELAY_TAB_ID": "11111111-2222-3333-4444-555555555555"],
        now: epoch
    )
    #expect(event?.sessionId == "")
    #expect(event?.paneId == "11111111-2222-3333-4444-555555555555")
}

@Test func clearAndResumeMarkReEngagement() {
    for source in ["clear", "resume"] {
        let event = ClaudeHookEvent.make(
            requested: .idle,
            payload: ["hook_event_name": "SessionStart", "source": source],
            env: [:],
            now: epoch
        )
        #expect(event?.resetsAttention == true)
    }
    let startup = ClaudeHookEvent.make(
        requested: .idle,
        payload: ["hook_event_name": "SessionStart", "source": "startup"],
        env: [:],
        now: epoch
    )
    #expect(startup?.resetsAttention == false)
}

@Test func promptingToolPreToolUseBecomesNeedsInput() {
    let event = ClaudeHookEvent.make(
        requested: .running,
        payload: ["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion"],
        env: [:],
        now: epoch
    )
    #expect(event?.state == .needsInput)
}

@Test func plainEventCarriesRequestedStateAndTimestamp() {
    let event = ClaudeHookEvent.make(requested: .running, payload: nil, env: [:], now: epoch)
    #expect(event?.state == .running)
    #expect(event?.agent == "claude")
    #expect(event?.timestamp == epoch)
    #expect(event?.resetsAttention == false)
}
