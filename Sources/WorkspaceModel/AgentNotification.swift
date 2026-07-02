import AgentProtocol

/// Tipo di notifica macOS meritata da una transizione di stato agente.
public enum AgentNotificationKind: Sendable, Equatable {
    /// Claude chiede input (entrata nello stato `needs_input`).
    case needsInput
    /// Lavoro finito (running -> idle) mentre la tab non era in vista.
    case completed
}

/// Richiesta di notifica emessa dallo store quando una transizione la merita. Dato puro: wiring a
/// `UNUserNotificationCenter`, preferenze e soppressione (app in primo piano) vivono nel
/// composition root (`RelayApp`), non qui.
public struct AgentNotification: Sendable, Equatable {
    public let kind: AgentNotificationKind
    public let tabTitle: String
    public let workspaceName: String
    /// La tab era quella in vista in Relay. Il coordinatore la usa per sopprimere il caso "la stai
    /// già guardando e Relay è in primo piano".
    public let isVisible: Bool

    public init(
        kind: AgentNotificationKind,
        tabTitle: String,
        workspaceName: String,
        isVisible: Bool
    ) {
        self.kind = kind
        self.tabTitle = tabTitle
        self.workspaceName = workspaceName
        self.isVisible = isVisible
    }
}
