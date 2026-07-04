import AgentProtocol
import AgentRuntime
import Foundation
import HookInstaller

/// Comando invocato dagli hook Claude: `relay-cli claude-hook <state>`. Legge lo stdin JSON di
/// Claude (per `session_id` e il `source` del SessionStart) e `RELAY_TAB_ID` dall'env (binding
/// pane), poi manda un `AgentStateEvent` al socket del receiver. Fail-safe: qualunque errore ->
/// exit 0 silenzioso, così un problema di Relay non rompe mai Claude.
enum ClaudeHookCommand {
    static func run(stateArg: String?) -> Int32 {
        guard let stateArg, let requested = AgentState(rawValue: stateArg) else { return 0 }

        let env = ProcessInfo.processInfo.environment
        let paneId = env["RELAY_TAB_ID"]
        let stdin = FileHandle.standardInput.readDataToEndOfFile()
        let payload = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any]
        let hookEventName = payload?["hook_event_name"] as? String
        let source = payload?["source"] as? String

        // Rumore da non inoltrare (es. SessionStart/compact a metà turno): fingerebbe un
        // completamento. Vedi ClaudeHookStateMapper.shouldSuppress.
        if ClaudeHookStateMapper.shouldSuppress(hookEventName: hookEventName, source: source) {
            return 0
        }

        let event = AgentStateEvent(
            agent: "claude",
            sessionId: sessionId(from: payload, env: env) ?? paneId ?? "unknown",
            paneId: paneId,
            // Il PreToolUse di un tool che apre un prompt bloccante (AskUserQuestion,
            // ExitPlanMode) è "aspetta input", non "sta lavorando": vedi il mapper.
            state: ClaudeHookStateMapper.effectiveState(
                requested: requested,
                hookEventName: hookEventName,
                toolName: payload?["tool_name"] as? String
            ),
            source: .hook,
            confidence: 1,
            timestamp: Date(),
            resetsAttention: isReEngagement(source: source)
        )
        try? AgentEventClient.send(event)
        return 0
    }

    private static func sessionId(from payload: [String: Any]?, env: [String: String]) -> String? {
        if let sid = payload?["session_id"] as? String, !sid.isEmpty { return sid }
        if let sid = env["CLAUDE_SESSION_ID"], !sid.isEmpty { return sid }
        return nil
    }

    /// `/clear` e `/new` (e la ripresa di una conversazione) arrivano come `SessionStart` con un
    /// `source` dedicato: sono ri-prese attive che risolvono il completamento in sospeso. `startup`
    /// (avvio normale) e `compact` (il contesto resta) NON lo sono. Il campo `source` esiste solo
    /// sul SessionStart, quindi discrimina da solo (uno `Stop` idle non ce l'ha).
    private static func isReEngagement(source: String?) -> Bool {
        source == "clear" || source == "resume"
    }
}
