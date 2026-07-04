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
    /// Timestamp dell'ultimo evento agente applicato. Avanza a **ogni** evento (anche i no-op:
    /// idle->idle, SessionEnd) perché è il clock della guardia di monotonicità. Non usarlo per
    /// l'età
    /// del marker né per la decadenza: userebbe l'ora di un evento che non ha toccato il marker
    /// (vedi `attentionSince`).
    public var lastEventAt: Date?
    /// Da quando il marker di attenzione corrente è in vigore: timbrato quando il marker nasce
    /// (completamento) e quando l'interazione lo declassa a `pending` (la vista "resetta" il
    /// clock).
    /// Distinto da `lastEventAt`: guida l'età del sospeso nella dashboard e la decadenza, così un
    /// evento no-op non ne falsifica l'età né posticipa il decay. `nil` se non c'è marker.
    public var attentionSince: Date?

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
        attentionSince: Date? = nil,
        resume: ResumeBinding? = nil
    ) {
        self.id = id
        self.title = title
        self.hasCustomTitle = hasCustomTitle
        self.currentDirectory = currentDirectory
        self.agentState = agentState
        self.attention = attention
        self.lastEventAt = lastEventAt
        self.attentionSince = attentionSince
        self.resume = resume
    }

    /// Applica il risultato del reducer per un evento arrivato a `timestamp`. `lastEventAt` avanza
    /// sempre (clock della monotonicità); `attentionSince` si timbra solo quando il marker nasce o
    /// cambia livello, così un no-op (SessionEnd che preserva l'unseen, idle->idle) non ne
    /// ringiovanisce l'età né posticipa la decadenza.
    func apply(_ result: AgentStateReducer.Result, at timestamp: Date) {
        let previousAttention = attention
        agentState = result.state
        attention = result.attention
        lastEventAt = timestamp
        if result.attention == .none {
            attentionSince = nil
        } else if result.attention != previousAttention {
            attentionSince = timestamp
        }
    }

    /// Declassa un completamento non visto (`unseen`) a "in sospeso" (`pending`): l'utente ha
    /// interagito col terminale, quindi l'ha visto ma non ripreso. Timbra `attentionSince` col
    /// momento della vista, che diventa il nuovo clock della decadenza. No-op se non è `unseen`
    /// (guardare non è occuparsene: la risoluzione vera è la ripresa, il dismiss o la chiusura).
    public func markSeen(at now: Date = Date()) {
        guard attention == .unseen else { return }
        attention = .pending
        attentionSince = now
    }

    /// C'è una sessione da riprendere e nessuna viva: dopo il restore (`agentState` riparte
    /// `unknown`) con un binding salvato. Guida la barra di resume; si spegne appena la sessione
    /// riparte (stato != unknown).
    public var pendingResume: Bool {
        resume != nil && agentState == .unknown
    }
}
