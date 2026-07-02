import AgentProtocol
import AgentRuntime
import Foundation

/// Comando invocato dagli hook Claude: `relay-cli claude-hook <state>`. Legge lo stdin JSON di
/// Claude (per `session_id`) e `RELAY_TAB_ID` dall'env (binding pane), poi manda un
/// `AgentStateEvent` al socket del receiver. Fail-safe: qualunque errore -> exit 0 silenzioso, così
/// un problema di Relay non rompe mai Claude.
enum ClaudeHookCommand {
    static func run(stateArg: String?) -> Int32 {
        guard let stateArg, let state = AgentState(rawValue: stateArg) else { return 0 }

        let env = ProcessInfo.processInfo.environment
        let paneId = env["RELAY_TAB_ID"]
        let stdin = FileHandle.standardInput.readDataToEndOfFile()

        let event = AgentStateEvent(
            agent: "claude",
            sessionId: sessionId(fromStdin: stdin, env: env) ?? paneId ?? "unknown",
            paneId: paneId,
            state: state,
            source: .hook,
            confidence: 1,
            timestamp: Date()
        )
        try? AgentEventClient.send(event)
        return 0
    }

    private static func sessionId(fromStdin data: Data, env: [String: String]) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let sid = object?["session_id"] as? String, !sid.isEmpty { return sid }
        if let sid = env["CLAUDE_SESSION_ID"], !sid.isEmpty { return sid }
        return nil
    }
}
