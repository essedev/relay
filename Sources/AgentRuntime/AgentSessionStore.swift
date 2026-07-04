import AgentProtocol
import Foundation

/// Store dello stato agente per sessione. Actor: aggiornato dagli eventi in arrivo dal receiver,
/// letto dalla UI. Snapshot corrente; la timeline completa arriva quando serve.
public actor AgentSessionStore {
    private var latest: [String: AgentStateEvent] = [:]

    public init() {}

    public func apply(_ event: AgentStateEvent) {
        // Guardia di monotonicità, come nello store UI: un evento consegnato in ritardo non deve
        // far regredire lo snapshot della sessione.
        if let current = latest[event.sessionId], event.timestamp < current.timestamp { return }
        latest[event.sessionId] = event
    }

    public func state(for sessionId: String) -> AgentStateEvent? {
        latest[sessionId]
    }

    public func all() -> [AgentStateEvent] {
        Array(latest.values)
    }
}
