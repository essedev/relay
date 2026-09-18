import AgentProtocol
import AgentRuntime
import Foundation
import HookInstaller

/// Comando fail-safe invocato dagli hook Codex: un problema di Relay non deve mai interrompere
/// Codex, quindi input non valido ed errori di trasporto terminano silenziosamente con exit 0.
enum CodexHookCommand {
    static func run(stateArg: String?) -> Int32 {
        guard let stateArg, let requested = AgentState(rawValue: stateArg) else { return 0 }

        let env = ProcessInfo.processInfo.environment
        let stdin = FileHandle.standardInput.readDataToEndOfFile()
        let payload = try? JSONSerialization.jsonObject(with: stdin) as? [String: Any]
        guard let event = CodexHookEvent.make(
            requested: requested,
            payload: payload,
            env: env,
            now: Date()
        ) else { return 0 }

        try? AgentEventClient.send(event)
        return 0
    }
}
