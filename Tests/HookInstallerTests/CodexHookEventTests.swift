import AgentProtocol
import Foundation
import HookInstaller
import Testing

private let codexEpoch = Date(timeIntervalSince1970: 1000)

@Test func codexEventCarriesIdentityAndSession() {
    let event = CodexHookEvent.make(
        requested: .running,
        payload: ["session_id": "thread-1", "hook_event_name": "UserPromptSubmit"],
        env: ["RELAY_TAB_ID": "tab", "RELAY_RUN_ID": "run"],
        now: codexEpoch
    )
    #expect(event?.agent == "codex")
    #expect(event?.sessionId == "thread-1")
    #expect(event?.paneId == "tab")
    #expect(event?.runId == "run")
}

@Test func codexCompactIsSuppressed() {
    let event = CodexHookEvent.make(
        requested: .idle,
        payload: ["hook_event_name": "SessionStart", "source": "compact"],
        env: [:],
        now: codexEpoch
    )
    #expect(event == nil)
}

@Test func codexInterruptDoesNotLookLikeCompletion() {
    let event = CodexHookEvent.make(
        requested: .idle,
        payload: ["hook_event_name": "Interrupt"],
        env: [:],
        now: codexEpoch
    )
    #expect(event?.state == .idle)
    #expect(event?.resetsAttention == true)
}

@Test func codexPromptingToolNeedsInput() {
    let event = CodexHookEvent.make(
        requested: .running,
        payload: ["hook_event_name": "PreToolUse", "tool_name": "request_user_input"],
        env: [:],
        now: codexEpoch
    )
    #expect(event?.state == .needsInput)
}
