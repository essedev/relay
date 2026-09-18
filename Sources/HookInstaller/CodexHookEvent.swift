import AgentProtocol
import Foundation

/// Traduce il payload JSON di un hook Codex nell'evento normalizzato consumato da Relay.
public enum CodexHookEvent {
    public static func make(
        requested: AgentState,
        payload: [String: Any]?,
        env: [String: String],
        now: Date
    ) -> AgentStateEvent? {
        let hookEventName = payload?["hook_event_name"] as? String
        let source = payload?["source"] as? String
        guard !CodexHookStateMapper.shouldSuppress(
            hookEventName: hookEventName,
            source: source
        ) else { return nil }

        return AgentStateEvent(
            agent: "codex",
            sessionId: sessionId(payload: payload, env: env) ?? "",
            paneId: env["RELAY_TAB_ID"],
            runId: env["RELAY_RUN_ID"],
            state: CodexHookStateMapper.effectiveState(
                requested: requested,
                hookEventName: hookEventName,
                toolName: payload?["tool_name"] as? String
            ),
            source: .hook,
            confidence: 1,
            timestamp: now,
            resetsAttention: CodexHookStateMapper.resetsAttention(
                hookEventName: hookEventName,
                source: source
            )
        )
    }

    static func sessionId(payload: [String: Any]?, env: [String: String]) -> String? {
        if let sid = payload?["session_id"] as? String, !sid.isEmpty { return sid }
        if let sid = env["CODEX_THREAD_ID"], !sid.isEmpty { return sid }
        return nil
    }
}
