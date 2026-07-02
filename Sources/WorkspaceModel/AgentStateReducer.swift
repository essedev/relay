import AgentProtocol

/// Regole pure di transizione dello stato agente di una tab, in risposta a un evento hook.
/// Isolate qui (niente UI, niente I/O) così sono testabili in isolamento; il coordinatore nel
/// composition root le applica al `Tab`.
public enum AgentStateReducer {
    public struct Result: Equatable {
        public let state: AgentState
        /// Marker "completato non visto": lavoro finito (running -> idle) mentre non guardavi. Si
        /// spegne alla visita. NON copre `needs_input`/`error`, che sono stati mostrati dal badge
        /// finché lo stato non cambia (es. `needs_input` resta finché rispondi a Claude).
        public let attention: Bool

        public init(state: AgentState, attention: Bool) {
            self.state = state
            self.attention = attention
        }
    }

    /// Calcola stato e `attention` dopo un evento.
    /// - `current`: stato attuale della tab.
    /// - `incoming`: stato dell'evento appena arrivato.
    /// - `isVisible`: la tab è quella attualmente in vista (workspace + tab selezionati).
    /// - `currentAttention`: valore attuale del marker.
    public static func reduce(
        current: AgentState,
        incoming: AgentState,
        isVisible: Bool,
        currentAttention: Bool
    ) -> Result {
        // Anti-rumore: idle -> idle non cambia nulla (la sessione era già ferma).
        if incoming == .idle, current == .idle {
            return Result(state: .idle, attention: currentAttention)
        }

        // `attention` = solo "completato non visto". needs_input/error non lo usano: il loro badge
        // è guidato dallo stato e resta finché lo stato cambia.
        let attention: Bool = if isVisible {
            false // visitando spegni il marker di completamento
        } else if incoming == .idle, current == .running {
            true // lavoro completato mentre la tab non era in vista
        } else {
            currentAttention
        }

        return Result(state: incoming, attention: attention)
    }
}
