import Core
import Foundation
import WorkspaceModel

/// Il lato passivo della nomina: chi è eleggibile, quando gira il poll e cosa decide a ogni tick.
/// Separato dal corpo di `NamingController` (che tiene stato, azione manuale e richiesta) per il
/// budget di dimensione, come le extension per area di `AppController`.
@MainActor
extension NamingController {
    /// Si ri-arma sui cambi (Observation): legge `settings.workspaceNamingEnabled` e i `nameOrigin`
    /// dei workspace, così creare un workspace `.default` o cambiare il toggle riaccende/spegne il
    /// timer. Qui si rilegge anche la chiave (non osservabile, quindi ri-valutata via
    /// `reconfigure()`), ma solo per sapere **chi** scriverà il nome: senza, il poll gira lo stesso
    /// e nomina in locale.
    func armEligibilityObserver() {
        observerGeneration += 1
        let generation = observerGeneration
        let eligible = withObservationTracking {
            settings.workspaceNamingEnabled
                && store.workspaces.contains { !$0.archived && $0.nameOrigin == .default }
        } onChange: { [weak self] in
            Task { @MainActor in
                // Un osservatore di una generazione precedente ha già un successore: lasciarlo
                // ri-armare moltiplicherebbe gli osservatori a ogni `reconfigure`/`regenerate`.
                guard let controller = self, generation == controller.observerGeneration
                else { return }
                controller.armEligibilityObserver()
            }
        }
        // Unico punto in cui la chiave si rilegge dal disco: da qui in poi il poll usa la cache.
        // Non è una condizione di eleggibilità: senza chiave si nomina lo stesso, in locale.
        apiKey = credentials.loadKey()
        if eligible {
            startTimer()
        } else {
            stopTimer()
        }
    }

    /// La chiave per una richiesta: la cache, o una rilettura se la cache è vuota. La rilettura
    /// copre l'azione manuale su una chiave comparsa senza passare dalle impostazioni (file scritto
    /// a mano): è rara e costa un accesso a file, mentre nel poll la cache regge sempre.
    func resolvedAPIKey() -> String? {
        if let apiKey { return apiKey }
        apiKey = credentials.loadKey()
        return apiKey
    }

    func startTimer() {
        guard timer == nil else { return }
        let interval = Self.pollInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Poll

    func poll() {
        guard settings.workspaceNamingEnabled else {
            stopTimer()
            return
        }
        let now = Date()
        prune(to: Set(store.workspaces.map(\.id)))
        let due = store.workspaces.filter {
            isEligible($0) && !isCoolingDown($0.id, now: now)
        }
        for workspace in due {
            evaluate(workspace, now: now)
        }
    }

    func isEligible(_ workspace: Workspace) -> Bool {
        !workspace.archived
            && workspace.nameOrigin == .default
            && !abandoned.contains(workspace.id)
            && !inFlight.contains(workspace.id)
    }

    func isCoolingDown(_ id: UUID, now: Date) -> Bool {
        guard let until = retryAfter[id] else { return false }
        guard now < until else {
            retryAfter[id] = nil
            return false
        }
        return true
    }

    /// Osserva il workspace e delega la decisione alla `NamingTriggerPolicy` pura; se decide di
    /// nominare, produce il nome. La priorità dei segnali (agente > comando stabile > cwd
    /// stabilizzata) vive nella policy, la scelta della tab da cui leggerli in `collectSignals`.
    ///
    /// Con una API key il nome lo chiede il modello; senza, lo deriva `WorkspaceNaming.localNames`
    /// e si applica subito. I trigger sono gli stessi: cambia solo chi scrive la stringa.
    func evaluate(_ workspace: Workspace, now: Date) {
        let observed = collectSignals(for: workspace)
        var policy = policies[workspace.id] ?? NamingTriggerPolicy()
        let decision = policy.observe(
            agent: observed.agent,
            command: observed.command,
            cwd: observed.directory,
            now: now
        )
        policies[workspace.id] = policy
        guard case let .name(signals) = decision else { return }
        guard let apiKey else {
            applyLocalName(workspace.id, signals: signals)
            return
        }
        guard let prompt = WorkspaceNaming.prompt(for: signals, homePath: homePath) else { return }
        fire(workspace.id, signals: signals, prompt: prompt, apiKey: apiKey, manual: false)
    }
}
