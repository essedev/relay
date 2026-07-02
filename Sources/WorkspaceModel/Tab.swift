import AgentProtocol
import Foundation

/// Una tab dentro un workspace. V0: una tab = un terminale (identificato da `id`).
/// La gerarchia a split (pane tree) potrà appendersi qui in futuro senza cambiare l'API esterna.
@Observable
public final class Tab: Identifiable {
    /// Titolo di una tab appena nata, prima che il programma ne imposti uno via OSC.
    public static let defaultTitle = "shell"

    public let id: UUID
    public var title: String
    /// L'utente ha rinominato la tab: non sovrascrivere il titolo con l'OSC del programma.
    public var hasCustomTitle: Bool
    /// Working directory corrente riportata dalla shell (OSC 7). Alimenta il titolo contestuale.
    public var currentDirectory: String?

    /// Stato agente corrente della sessione legata a questa tab. Guida il badge e l'aggregazione
    /// per severità nella sidebar. `.unknown` finché non arriva un evento hook.
    public var agentState: AgentState
    /// Marker "completato non visto": lavoro finito (running -> idle) mentre la tab non era in
    /// vista. Si spegne alla visita. Distinto dallo stato: `running`/`needs_input`/`error` sono
    /// mostrati dal badge in base ad `agentState` finché lo stato non cambia (`needs_input` resta
    /// finché rispondi a Claude, non si spegne al focus).
    public var attention: Bool
    /// Timestamp dell'ultimo evento agente applicato.
    public var lastEventAt: Date?

    public init(
        id: UUID = UUID(),
        title: String = Tab.defaultTitle,
        hasCustomTitle: Bool = false,
        currentDirectory: String? = nil,
        agentState: AgentState = .unknown,
        attention: Bool = false,
        lastEventAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.hasCustomTitle = hasCustomTitle
        self.currentDirectory = currentDirectory
        self.agentState = agentState
        self.attention = attention
        self.lastEventAt = lastEventAt
    }
}
