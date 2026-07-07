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
    /// Identità della run dell'app che ha generato la surface (`RELAY_RUN_ID`, ereditato via env
    /// come `RELAY_TAB_ID`). Il timestamp non basta a distinguere gli eventi di questa run da
    /// quelli di sessioni orfane di run precedenti (i loro hook girano *adesso*, quindi passano
    /// ogni soglia temporale): il fence dello store scarta gli eventi la cui run non è la sua.
    /// `nil` = CLI vecchio o processo fuori da una surface di questa run.
    public let runId: String?
    public let state: AgentState
    public let source: AgentStateSource
    public let confidence: Double
    public let timestamp: Date
    /// L'evento è una ri-presa attiva della conversazione (SessionStart `clear`/`resume`), non un
    /// semplice stato: risolve il marker di attenzione (`AttentionLevel`). Lo `state` resta `.idle`
    /// (l'agente dopo clear/resume è comunque fermo in attesa), il flag ne cambia solo l'effetto
    /// sul
    /// completamento in sospeso. Default `false`; decode retrocompatibile (chiave assente = false).
    public let resetsAttention: Bool

    public init(
        agent: String,
        sessionId: String,
        paneId: String?,
        runId: String? = nil,
        state: AgentState,
        source: AgentStateSource,
        confidence: Double,
        timestamp: Date,
        resetsAttention: Bool = false
    ) {
        self.agent = agent
        self.sessionId = sessionId
        self.paneId = paneId
        self.runId = runId
        self.state = state
        self.source = source
        self.confidence = confidence
        self.timestamp = timestamp
        self.resetsAttention = resetsAttention
    }

    /// Decode tollerante: un evento da un CLI più vecchio (senza `resetsAttention`/`runId`) resta
    /// valido.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agent = try container.decode(String.self, forKey: .agent)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        paneId = try container.decodeIfPresent(String.self, forKey: .paneId)
        runId = try container.decodeIfPresent(String.self, forKey: .runId)
        state = try container.decode(AgentState.self, forKey: .state)
        source = try container.decode(AgentStateSource.self, forKey: .source)
        confidence = try container.decode(Double.self, forKey: .confidence)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        resetsAttention = try container
            .decodeIfPresent(Bool.self, forKey: .resetsAttention) ?? false
    }
}
