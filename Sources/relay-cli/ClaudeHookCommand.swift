import AgentProtocol
import AgentRuntime
import Foundation
import HookInstaller

/// Comando invocato dagli hook Claude: `relay-cli claude-hook <state>`. Legge lo stdin JSON di
/// Claude (per `session_id` e il `source` del SessionStart) e `RELAY_TAB_ID` dall'env (binding
/// pane), poi manda un `AgentStateEvent` al socket del receiver. La costruzione dell'evento (pura)
/// vive in `ClaudeHookEvent`; qui restano solo l'I/O e il fail-safe: qualunque errore -> exit 0
/// silenzioso, così un problema di Relay non rompe mai Claude.
enum ClaudeHookCommand {
    static func run(stateArg: String?) -> Int32 {
        guard let stateArg, let requested = AgentState(rawValue: stateArg) else { return 0 }

        let env = ProcessInfo.processInfo.environment
        let stdin = FileHandle.standardInput.readDataToEndOfFile()
        let payload = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any]

        guard let event = ClaudeHookEvent.make(
            requested: requested,
            payload: payload,
            env: env,
            now: Date()
        ) else { return 0 } // evento soppresso (rumore, es. compact a metà turno)

        try? AgentEventClient.send(event)
        return 0
    }
}
