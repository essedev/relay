import AgentProtocol
import Foundation

/// Costruisce l'`AgentStateEvent` da inviare al socket a partire dal payload JSON dell'hook e
/// dall'ambiente, senza I/O: così il path stdin -> evento (soppressione compact, correzione dei
/// prompting tool, sessionId, resetsAttention) è testabile fuori dall'eseguibile CLI, dove
/// `ClaudeHookCommand` lo invoca con stdin ed env reali.
public enum ClaudeHookEvent {
    /// L'evento da inviare, o `nil` se va soppresso (rumore, es. SessionStart/compact a metà
    /// turno).
    public static func make(
        requested: AgentState,
        payload: [String: Any]?,
        env: [String: String],
        now: Date
    ) -> AgentStateEvent? {
        let hookEventName = payload?["hook_event_name"] as? String
        let source = payload?["source"] as? String
        guard !ClaudeHookStateMapper.shouldSuppress(hookEventName: hookEventName, source: source)
        else { return nil }

        return AgentStateEvent(
            agent: "claude",
            // Sessione sconosciuta -> stringa vuota (lo store salta il resume binding); mai il
            // paneId, con cui `claude --resume <tab-id>` fallirebbe.
            sessionId: sessionId(payload: payload, env: env) ?? "",
            paneId: env["RELAY_TAB_ID"],
            // Identità della run che ha creato la surface: l'app scarta gli eventi di run diverse
            // (hook di sessioni orfane sopravvissute a un riavvio).
            runId: env["RELAY_RUN_ID"],
            // Un prompting tool bloccante (AskUserQuestion/ExitPlanMode) è "aspetta input": vedi
            // il mapper.
            state: ClaudeHookStateMapper.effectiveState(
                requested: requested,
                hookEventName: hookEventName,
                toolName: payload?["tool_name"] as? String
            ),
            source: .hook,
            confidence: 1,
            timestamp: now,
            resetsAttention: isReEngagement(source: source)
        )
    }

    static func sessionId(payload: [String: Any]?, env: [String: String]) -> String? {
        if let sid = payload?["session_id"] as? String, !sid.isEmpty { return sid }
        if let sid = env["CLAUDE_SESSION_ID"], !sid.isEmpty { return sid }
        return nil
    }

    /// `/clear`, `/new` e la ripresa arrivano come `SessionStart` con un `source` dedicato: sono
    /// ri-prese attive che risolvono il completamento in sospeso. `startup` e `compact` no (il
    /// secondo è comunque soppresso a monte).
    static func isReEngagement(source: String?) -> Bool {
        source == "clear" || source == "resume"
    }
}
