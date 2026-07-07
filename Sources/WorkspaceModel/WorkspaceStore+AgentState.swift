import AgentProtocol
import Foundation

// Stato agente e marker di attenzione dello store: applicazione degli eventi (guardia di
// monotonicità + notifiche), dismiss e decadenza dei sospesi. Estratto da `WorkspaceStore` per
// tenere il file principale entro il budget di dimensione (vedi CONVENTIONS). La logica è la
// stessa: agisce sui `Workspace`/`Tab` osservabili dello store.

public extension WorkspaceStore {
    // MARK: - Stato agente

    /// Applica un evento agente alla tab identificata da `paneId` (= `RELAY_TAB_ID` = `Tab.id`).
    /// `isVisible` = tab in vista **e** app in primo piano (`appActive`): se Relay è in background
    /// non la stai guardando davvero, anche se è la tab selezionata, quindi il completamento resta
    /// segnalato e la notifica parte. `appActive` lo passa il composition root (`NSApp.isActive`);
    /// default `true` per i test/chiamate diretti.
    /// Un evento più vecchio dell'ultimo applicato alla tab è stantio e viene scartato (guardia di
    /// monotonicità sul `timestamp`): gli hook sono processi concorrenti e il trasporto non
    /// garantisce l'ordine di consegna.
    /// Ritorna `false` se `paneId` non è un UUID valido o non corrisponde a nessuna tab (no-op).
    @discardableResult
    func applyAgentState(
        paneId: String,
        agent: String = "",
        sessionId: String = "",
        runId: String? = nil,
        state: AgentState,
        at timestamp: Date,
        appActive: Bool = true,
        resetsAttention: Bool = false
    ) -> Bool {
        guard let tabID = UUID(uuidString: paneId) else { return false }
        // Fence di run: un evento di una run diversa (o senza runId) non appartiene a una surface
        // di questa run, qualunque sia il suo timestamp. È l'hook di una sessione orfana
        // sopravvissuta a un riavvio (claude che ha ignorato il SIGHUP, SessionEnd morente che
        // scavalca un relaunch rapido): eseguito *adesso*, passerebbe la soglia temporale, e uno
        // `Stop`/`SessionEnd` sopprimerebbe la proposta di resume appena ripristinata (stato non
        // più `unknown` o binding azzerato).
        if let expected = runID, runId != expected { return true }
        // Soglia anti-stantio: un evento generato prima dell'avvio dell'app non può appartenere a
        // una surface di questa run (nascono dopo l'avvio), quindi è di una sessione già morta.
        // Scartarlo protegge il resume binding appena ripristinato, che il `RELAY_TAB_ID` stabile
        // esporrebbe a un `SessionEnd`/hook orfano in ritardo (che lo azzererebbe, sopprimendo la
        // proposta di resume). Complementare al fence di run: copre anche i CLI vecchi che non
        // mandano il runId, quando il fence è spento.
        if let floor = eventFloor, timestamp < floor { return true }
        for workspace in workspaces {
            guard let tab = workspace.tabs.first(where: { $0.id == tabID }) else { continue }
            // Guardia di monotonicità: un evento consegnato in ritardo non deve far regredire la
            // tab (un running residuo che copre lo Stop già applicato, un SessionEnd stantio che
            // azzererebbe il resume vivo). Si scarta solo lo strettamente più vecchio: a parità
            // di timestamp (stesso millisecondo sul filo) vince l'ultimo arrivato, come prima.
            if let last = tab.lastEventAt, timestamp < last { return true }
            let isSelected = selectedWorkspaceID == workspace.id
                && workspace.selectedTabID == tab.id
            let isVisible = isSelected && appActive
            let previousState = tab.agentState
            let previousAttention = tab.attention
            let result = AgentStateReducer.reduce(
                current: previousState,
                incoming: state,
                isVisible: isVisible,
                currentAttention: tab.attention,
                resetsAttention: resetsAttention
            )
            tab.apply(result, at: timestamp)
            // Bump posizionale (modello lista chat): un'attività **non vista** - un completamento
            // (il marker nasce) o l'entrata in `needs_input` - porta il workspace in cima. Reale e
            // persistente, non float derivato. Simmetrico al segnale forte e alla notifica: solo
            // `!isVisible`. La ripresa (`running`) non muove niente: la riga su cui lavori resta
            // ferma; a scavalcarla è solo un altro bump o il tuo drag.
            let attentionBorn = previousAttention == .none && tab.attention != .none
            let enteredNeedsInput = previousState != .needsInput && tab.agentState == .needsInput
            if !isVisible, attentionBorn || enteredNeedsInput {
                bumpWorkspaceToTop(workspace.id)
            }
            // Notifica (needs_input / completato non visto): classificazione pura, effetto nel
            // composition root. Emessa dopo aver aggiornato la tab (titolo aggiornato dagli hook).
            if let kind = AgentStateReducer.notification(
                current: previousState,
                incoming: state,
                isVisible: isVisible,
                resetsAttention: resetsAttention
            ) {
                onNotifiableTransition?(AgentNotification(
                    kind: kind,
                    tabTitle: tab.title,
                    workspaceName: workspace.name,
                    isVisible: isVisible
                ))
            }
            // Resume binding: aggiornato finché la sessione è viva, azzerato alla chiusura
            // (`unknown` = SessionEnd). Si crea solo con componenti sicuri: sessionId/agent vuoti o
            // con metacaratteri non producono un binding che `autoResumeAgents` inietterebbe nel
            // pty.
            let safeToBind = ResumeBinding.isSafeComponent(sessionId)
                && ResumeBinding.isSafeComponent(agent)
            if state == .unknown {
                tab.resume = nil
            } else if safeToBind {
                tab.resume = ResumeBinding(agent: agent, sessionId: sessionId, label: tab.title)
            }
            return true
        }
        return false
    }

    // MARK: - Attenzione (dismiss e decadenza)

    /// Dismiss esplicito dell'attenzione di una tab ("era done, niente da fare"): spegne il
    /// marker a qualunque livello (unseen o pending). Ritorna `true` se c'era qualcosa da spegnere.
    @discardableResult
    func dismissAttention(_ tabID: UUID) -> Bool {
        for workspace in workspaces {
            guard let tab = workspace.tabs.first(where: { $0.id == tabID }) else { continue }
            guard tab.attention != .none else { return false }
            tab.attention = .none
            tab.attentionSince = nil
            return true
        }
        return false
    }

    /// Toggle manuale del marker dal menu contestuale (sidebar/tab bar): se la tab ha attenzione
    /// (unseen o pending) la spegne ("Mark as Read"), altrimenti riaccende il segnale forte
    /// ("Mark as Unread"). Cerca la tab per id fra tutti i workspace, come `dismissAttention`.
    func toggleUnread(_ tabID: UUID) {
        guard let tab = workspaces.flatMap(\.tabs).first(where: { $0.id == tabID }) else { return }
        if tab.attention == .none {
            tab.markUnread()
        } else {
            tab.attention = .none
            tab.attentionSince = nil
        }
    }

    /// Decadenza opzionale dei sospesi: spegne i `pending` diventati tali prima di `cutoff`.
    /// Chiamata dal composition root quando la preferenza è attiva (boot, ritorno in foreground,
    /// apertura dashboard). Misura da `attentionSince` (da quando è in sospeso), non da
    /// `lastEventAt` (l'evento): un completamento mai visto degrada a pending al restore con clock
    /// dal boot, quindi non viene spazzato subito. Ritorna quanti ne ha spenti.
    @discardableResult
    func decayPending(olderThan cutoff: Date) -> Int {
        var decayed = 0
        for tab in workspaces.flatMap(\.tabs) {
            guard tab.attention == .pending,
                  (tab.attentionSince ?? tab.lastEventAt ?? .distantPast) < cutoff else { continue }
            tab.attention = .none
            tab.attentionSince = nil
            decayed += 1
        }
        return decayed
    }
}
