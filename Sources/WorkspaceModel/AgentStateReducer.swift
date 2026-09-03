import AgentProtocol

/// Regole pure di transizione dello stato agente di una tab, in risposta a un evento hook.
/// Isolate qui (niente UI, niente I/O) così sono testabili in isolamento; il coordinatore nel
/// composition root le applica al `Tab`.
public enum AgentStateReducer {
    public struct Result: Equatable {
        public let state: AgentState
        /// Marker di attenzione (vedi `AttentionLevel`). Lo accendono il completamento e
        /// l'errore: entrambi sono novità che nascono da Claude mentre non guardavi, e il marker
        /// è il canale che le porta in cima alla sidebar e accende il ring. NON copre
        /// `needs_input`, che il badge mostra da `agentState` finché rispondi.
        public let attention: AttentionLevel

        public init(state: AgentState, attention: AttentionLevel) {
            self.state = state
            self.attention = attention
        }
    }

    /// Calcola stato e `attention` dopo un evento.
    /// - `current`: stato attuale della tab.
    /// - `incoming`: stato dell'evento appena arrivato.
    /// - `currentAttention`: livello attuale del marker.
    /// - `resetsAttention`: l'evento è una ri-presa attiva della conversazione (clear/resume): come
    ///   il primo prompt, dimostra che te ne stai occupando (o che hai buttato il contesto), quindi
    ///   risolve il completamento in sospeso a prescindere dallo stato in ingresso.
    ///
    /// Nota: il livello nascente **non** dipende dalla visibilità. Un completamento nasce sempre
    /// col segnale forte (`unseen`); se la tab è in vista è il composition root a declassarlo a
    /// `pending` dopo un breve flash (mark-read differito, vedi gotcha attention), non il reducer.
    /// La visibilità resta rilevante solo per bump e notifiche, calcolati fuori di qui.
    public static func reduce(
        current: AgentState,
        incoming: AgentState,
        currentAttention: AttentionLevel,
        resetsAttention: Bool = false
    ) -> Result {
        // Ri-presa attiva (clear/resume): spegne il marker. Prima dell'anti-rumore idle->idle, che
        // altrimenti preserverebbe il sospeso residuo del completamento precedente.
        if resetsAttention {
            return Result(state: incoming, attention: .none)
        }

        // Anti-rumore: idle -> idle non cambia nulla (la sessione era già ferma).
        if incoming == .idle, current == .idle {
            return Result(state: .idle, attention: currentAttention)
        }

        let attention: AttentionLevel = switch incoming {
        case .running, .needsInput:
            // La conversazione si è mossa (il tuo prompt, un permesso): la ripresa vera risolve il
            // completamento, visto o in sospeso che fosse.
            .none
        case .error:
            // Turno morto per errore API: novità forte quanto un completamento, e più urgente.
            // Nasce sempre `unseen`, anche sopra un sospeso già declassato a `pending`: un errore
            // nuovo è un fatto nuovo, non la coda di quello vecchio. Il declassamento sulla tab in
            // vista lo fa il composition root col solito flash, come per il completamento.
            .unseen
        case .idle:
            // Lavoro completato: nasce sempre col segnale forte (`unseen`). Sulla tab in vista il
            // composition root lo declassa a `pending` dopo un breve flash; se non guardavi resta
            // forte finché non lo vedi.
            current == .running ? .unseen : currentAttention
        case .unknown:
            // Fine sessione: un completamento mai ripreso resta tale (la tab e il suo output
            // esistono ancora); si spegne solo con dismiss, decadenza o chiusura tab.
            currentAttention
        }

        return Result(state: incoming, attention: attention)
    }

    /// Decide se una transizione merita una notifica macOS (nil = nessuna). Notifichiamo ogni
    /// transizione che porta informazione che l'utente non ha già, cioè i tre stati che nascono da
    /// Claude: `needs_input`, `error` e il completamento. `running` e `unknown` restano fuori di
    /// proposito, e non è un'omissione: `running` lo generano `UserPromptSubmit` e **ogni**
    /// `PreToolUse`/`PostToolUse` (decine di eventi per turno, tutti causati dal prompt che hai
    /// appena mandato) e `unknown` è `SessionEnd`, cioè `/clear`, `exit` o logout. Sono azioni
    /// dell'utente: notificarle seppellirebbe le tre che contano.
    ///
    /// Regole anti-rumore, le stesse dei badge:
    /// - `needs_input` alla *entrata* nello stato (non a ogni evento successivo);
    /// - `error` alla *entrata* nello stato: una raffica di retry falliti riaccende il badge ogni
    ///   volta ma notifica una sola volta;
    /// - `completed` solo se il lavoro finisce (running -> idle) mentre la tab non è in vista.
    ///
    /// Puro: la soppressione runtime (app in primo piano) e le preferenze utente le applica il
    /// composition root.
    public static func notification(
        current: AgentState,
        incoming: AgentState,
        isVisible: Bool,
        resetsAttention: Bool = false
    ) -> AgentNotificationKind? {
        // Una ri-presa attiva (clear/resume) non è mai un completamento da notificare, anche se per
        // caso arriva mentre lo stato era `running` (es. /clear a metà lavoro).
        if resetsAttention { return nil }
        if incoming == .needsInput, current != .needsInput {
            return .needsInput
        }
        if incoming == .error, current != .error {
            return .error
        }
        if incoming == .idle, current == .running, !isVisible {
            return .completed
        }
        return nil
    }
}
