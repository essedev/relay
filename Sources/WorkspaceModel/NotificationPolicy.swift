/// Ultimo filtro prima del banner macOS: preferenze dell'utente e soppressione di ciò che stai
/// già guardando, più il titolo che il banner mostra.
///
/// Sta qui e non nel composition root per una ragione pratica: `RelayApp` non ha un test target
/// (vedi CONVENTIONS, "UI: minimale"), quindi tutto ciò che decide qualcosa e vive lì dentro non
/// è coperto. `AgentStateReducer.notification` decide **se** una transizione merita una notifica;
/// questa decide **se consegnarla**, e insieme sono la regola completa. Al coordinatore resta
/// `UNUserNotificationCenter`, cioè solo I/O.
public enum NotificationPolicy {
    /// Le preferenze che contano, come valori: i toggle di Settings senza portarsi dietro
    /// `AppSettings` (e il suo `@MainActor`) nei test.
    public struct Preferences: Sendable, Equatable {
        public let enabled: Bool
        public let onNeedsInput: Bool
        public let onCompleted: Bool
        public let onError: Bool

        public init(
            enabled: Bool,
            onNeedsInput: Bool,
            onCompleted: Bool,
            onError: Bool
        ) {
            self.enabled = enabled
            self.onNeedsInput = onNeedsInput
            self.onCompleted = onCompleted
            self.onError = onError
        }
    }

    /// `isVisible` include già "Relay in primo piano" (vedi `applyAgentState`): se è vero la stai
    /// guardando, e needs_input o errore li leggi nel terminale prima che suoni qualcosa.
    /// Il completamento non ha bisogno dello stesso taglio perché il reducer non lo emette
    /// nemmeno quando la tab è in vista; il controllo resta lo stesso per tutti e tre, così la
    /// regola non dipende da quale chiamante la usa.
    public static func shouldDeliver(
        _ request: AgentNotification,
        given preferences: Preferences
    ) -> Bool {
        guard preferences.enabled, !request.isVisible else { return false }
        return switch request.kind {
        case .needsInput: preferences.onNeedsInput
        case .completed: preferences.onCompleted
        case .error: preferences.onError
        }
    }

    /// Titolo del banner. `agent` distingue Claude da Codex; se l'hook non lo manda resta un
    /// generico "Agent" invece di una riga monca.
    public static func title(for kind: AgentNotificationKind, agent: String) -> String {
        let name = switch agent.lowercased() {
        case "claude": "Claude"
        case "codex": "Codex"
        default: agent.isEmpty ? "Agent" : agent
        }
        return switch kind {
        case .needsInput: "\(name) needs a reply"
        case .completed: "\(name) finished"
        case .error: "\(name) stopped on an error"
        }
    }
}
