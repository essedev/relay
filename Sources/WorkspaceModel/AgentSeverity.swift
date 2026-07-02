import AgentProtocol

/// Aggregazione dello stato agente lungo la gerarchia pane -> tab -> workspace.
/// Ordine di severità (docs/ARCHITECTURE.md): needs_input > error > running > idle/unknown.
public enum AgentSeverity {
    /// Rango di severità di un singolo stato. Più alto = più urgente.
    public static func rank(_ state: AgentState) -> Int {
        switch state {
        case .needsInput: 4
        case .error: 3
        case .running: 2
        case .idle: 1
        case .unknown: 0
        }
    }

    /// Stato aggregato di un insieme: il più severo. Vuoto -> `.unknown`.
    public static func aggregate(_ states: some Sequence<AgentState>) -> AgentState {
        states.max { rank($0) < rank($1) } ?? .unknown
    }
}
