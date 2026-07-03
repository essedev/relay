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
    /// Attenzione post-completamento a tre livelli (vedi `AttentionLevel`): `unseen` = completato
    /// mentre non guardavi (forte), `pending` = visto ma mai ripreso (quieto, persistente).
    /// L'interazione declassa unseen -> pending; risolve solo la ripresa (prompt -> running), il
    /// dismiss o la chiusura. Distinto dallo stato: `running`/`needs_input`/`error` sono mostrati
    /// dal badge in base ad `agentState` finché lo stato non cambia (`needs_input` resta finché
    /// rispondi a Claude, non si spegne al focus).
    public var attention: AttentionLevel
    /// Timestamp dell'ultimo evento agente applicato.
    public var lastEventAt: Date?

    /// Sessione agente ripristinabile: settata mentre c'è una sessione viva, persistita, usata al
    /// restore per proporre il resume. `nil` se non c'è (mai stato un agente, o sessione chiusa).
    public var resume: ResumeBinding?

    public init(
        id: UUID = UUID(),
        title: String = Tab.defaultTitle,
        hasCustomTitle: Bool = false,
        currentDirectory: String? = nil,
        agentState: AgentState = .unknown,
        attention: AttentionLevel = .none,
        lastEventAt: Date? = nil,
        resume: ResumeBinding? = nil
    ) {
        self.id = id
        self.title = title
        self.hasCustomTitle = hasCustomTitle
        self.currentDirectory = currentDirectory
        self.agentState = agentState
        self.attention = attention
        self.lastEventAt = lastEventAt
        self.resume = resume
    }

    /// C'è una sessione da riprendere e nessuna viva: dopo il restore (`agentState` riparte
    /// `unknown`) con un binding salvato. Guida la barra di resume; si spegne appena la sessione
    /// riparte (stato != unknown).
    public var pendingResume: Bool {
        resume != nil && agentState == .unknown
    }
}
