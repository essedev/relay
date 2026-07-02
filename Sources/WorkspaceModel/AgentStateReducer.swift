import AgentProtocol

/// Regole pure di transizione dello stato agente di una tab, in risposta a un evento hook.
/// Isolate qui (niente UI, niente I/O) così sono testabili in isolamento; il coordinatore nel
/// composition root le applica al `Tab`.
public enum AgentStateReducer {
    public struct Result: Equatable {
        public let state: AgentState
        /// Marker "unread": c'è qualcosa da guardare non ancora visto.
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

        let attention: Bool = if isVisible {
            // La stai guardando: nessun marker unread, vedi lo stato dal vivo.
            false
        } else if incoming == .needsInput || incoming == .error {
            true
        } else if incoming == .idle, current == .running {
            // Lavoro completato mentre la tab non era in vista.
            true
        } else {
            currentAttention
        }

        return Result(state: incoming, attention: attention)
    }
}
