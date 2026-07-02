import Foundation

/// Tipi di evento del protocollo locale v1 (trasporto: Unix socket, JSON lines).
public enum AgentEventType: String, Sendable, Codable {
    case sessionStart = "agent.session.start"
    case state = "agent.state"
    case notification = "agent.notification"
    case resumeSet = "agent.resume.set"
    case sessionEnd = "agent.session.end"
}

/// Sorgente dello stato. Gli hook sono autorevoli; le euristiche no.
public enum AgentStateSource: String, Sendable, Codable {
    case hook
    case osc
    case shellIntegration = "shell_integration"
    case heuristic
}

/// Evento `agent.state`. Nessun campo sensibile (niente prompt, token, credenziali).
public struct AgentStateEvent: Sendable, Codable, Equatable {
    public let agent: String
    public let sessionId: String
    public let paneId: String?
    public let state: AgentState
    public let source: AgentStateSource
    public let confidence: Double
    public let timestamp: Date

    public init(
        agent: String,
        sessionId: String,
        paneId: String?,
        state: AgentState,
        source: AgentStateSource,
        confidence: Double,
        timestamp: Date
    ) {
        self.agent = agent
        self.sessionId = sessionId
        self.paneId = paneId
        self.state = state
        self.source = source
        self.confidence = confidence
        self.timestamp = timestamp
    }
}
