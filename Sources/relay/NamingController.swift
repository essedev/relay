import Core
import Foundation
import WorkspaceModel

/// Perché il "Regenerate name" manuale non ha prodotto un nome. La nomina **automatica** resta
/// silenziosa (mai un alert per un nome che non hai chiesto); quella manuale no: un'azione
/// esplicita che non fa niente e non dice niente è indistinguibile da un bug. Il controller non
/// presenta nulla, lo riporta al composition root (unico proprietario dell'UI).
enum NamingFailure: Equatable {
    /// Feature spenta o API key mancante: senza feedback resta invisibile per sempre.
    case notConfigured
    /// Nessun segnale utile: workspace fermo in home, senza comandi in corso né cartella nota.
    case noContext
    /// La richiesta è partita e non ne è uscito un nome (rete, HTTP, parse, sanitize).
    case requestFailed
}

/// Nomina automatica dei workspace via LLM (endpoint OpenAI-compatible). Vive nel composition root
/// (come `UpdateController`): è l'unico punto che tocca la rete per questa feature e lega la logica
/// pura allo store e alle surface. La policy dei trigger (`Core.NamingTriggerPolicy`), la
/// costruzione del prompt e la sanitizzazione (`Core.WorkspaceNaming`) stanno nel modulo puro
/// (testato); qui resta il wiring: eleggibilità, timer, letture della surface e rete.
///
/// Modello: un workspace `.default` (placeholder o nome-cartella) è "eleggibile"; un poll leggero
/// osserva **tutte le sue tab** e, al primo segnale utile, chiede un nome e lo applica
/// (`applyGeneratedName`, che degrada a no-op se nel frattempo l'utente ha rinominato a mano). Tre
/// segnali, dal più forte: agente attivo (Claude in `running`/`needs_input`) -> subito; comando in
/// foreground stabile (es. `brew update`) -> dopo qualche tick; cwd stabilizzata fuori dalla home
/// -> dopo ~10s. La cwd viene dalla shell **viva** (closure iniettata, precedenza in
/// `Core.CurrentDirectory`), non da `tab.currentDirectory` (solo OSC 7, che zsh in Relay non
/// emette). Single-flight per workspace, max 2 tentativi (distanziati da un cooldown) poi si
/// arrende in silenzio.
///
/// "Regenerate name" (`regenerate`) è l'azione **manuale**: nomina subito col contesto corrente
/// saltando le soglie della policy, chiede un nome **diverso** da quello attuale e, se non ce la
/// fa, lo dice (`onFailure` -> alert nel composition root). Il poll resta la rete di sicurezza per
/// il prossimo segnale.
///
/// Lazy: il timer di poll esiste **solo** quando la feature è configurata (abilitata + API key) e
/// c'è almeno un workspace `.default` da nominare (osservazione su `nameOrigin`); quando tutti sono
/// nominati il timer si ferma da solo. Il poll è comunque a costo trascurabile (un filtro su pochi
/// workspace ogni pochi secondi), fuori dal path caldo del terminale.
@MainActor
final class NamingController {
    private let store: WorkspaceStore
    private let settings: AppSettings
    private let credentials: NamingCredentialStore
    /// Chiamata all'endpoint OpenAI-compatible (`ChatCompletionClient`): qui si decide *quando*
    /// chiedere un nome, lì *come* si chiede.
    private let client: ChatCompletionClient
    private let homePath: String
    /// Argv del processo in foreground di una tab (iniettata: raggiunge lo split -> registry).
    private let foregroundCommandLine: (UUID) -> [String]?
    /// Cwd migliore nota per una tab (iniettata: `WorkspaceAreaController.currentDirectory`, con la
    /// precedenza shell viva -> ultimo OSC 7 -> root). **Non** `tab.currentDirectory`: quello è il
    /// solo OSC 7, che zsh in Relay non emette (vedi gotcha OSC 7), quindi il segnale cwd sarebbe
    /// sempre nil e la nomina da directory non scatterebbe mai.
    private let currentDirectory: (UUID) -> String?
    /// Feedback dell'azione manuale verso il composition root (che possiede l'UI). Il poll non la
    /// usa mai: la nomina automatica è silenziosa per design.
    private let onFailure: (UUID, NamingFailure) -> Void
    private let log = RelayLog.logger("naming")

    /// Intervallo del poll. Un compromesso: abbastanza reattivo per cogliere un `brew update` senza
    /// spammare. La latenza di nomina non è UX critica.
    private static let pollInterval: TimeInterval = 3
    /// Tentativi per workspace prima di arrendersi (errori di rete/parse/sanitize).
    private static let maxAttempts = 2
    /// Pausa dopo un tentativo fallito. Senza, la policy che ha già deciso "nomina" ridecide a ogni
    /// tick e i tentativi si bruciano in sei secondi: un singolo blip di rete spegneva la nomina
    /// del workspace per sempre.
    private static let retryCooldown: TimeInterval = 60

    private var timer: Timer?
    /// Richieste in volo per workspace (single-flight): non ne parte una seconda finché la prima
    /// non torna.
    private var inFlight: Set<UUID> = []
    /// Tentativi falliti per workspace; raggiunta la soglia il workspace entra in `abandoned`.
    private var attempts: [UUID: Int] = [:]
    /// Workspace per cui abbiamo smesso di provare (max tentativi): saltati dal poll.
    private var abandoned: Set<UUID> = []
    /// Fine del cooldown post-fallimento per workspace: il poll li salta fino a quel momento.
    /// L'azione manuale lo ignora (è una richiesta esplicita) e lo azzera.
    private var retryAfter: [UUID: Date] = [:]
    /// Policy dei trigger per workspace (streak comando + stabilizzazione cwd). Logica pura in
    /// `Core.NamingTriggerPolicy`; qui resta solo lo stato accumulato tick dopo tick.
    private var policies: [UUID: NamingTriggerPolicy] = [:]

    init(
        store: WorkspaceStore,
        settings: AppSettings,
        credentials: NamingCredentialStore,
        foregroundCommandLine: @escaping (UUID) -> [String]?,
        currentDirectory: @escaping (UUID) -> String?,
        onFailure: @escaping (UUID, NamingFailure) -> Void,
        session: URLSession = .shared,
        homePath: String = NSHomeDirectory()
    ) {
        self.store = store
        self.settings = settings
        self.credentials = credentials
        self.foregroundCommandLine = foregroundCommandLine
        self.currentDirectory = currentDirectory
        self.onFailure = onFailure
        client = ChatCompletionClient(session: session)
        self.homePath = homePath
    }

    /// Avvia l'osservazione dell'eleggibilità: il timer parte quando serve e si ferma quando non
    /// c'è più niente da nominare.
    func start() {
        armEligibilityObserver()
    }

    func stop() {
        stopTimer()
    }

    /// Da chiamare quando cambia la configurazione (toggle, base URL, model o API key salvata dalle
    /// impostazioni): ri-valuta se il timer deve girare (la presenza della chiave non è
    /// osservabile,
    /// quindi va notificata a mano).
    func reconfigure() {
        armEligibilityObserver()
    }

    /// "Regenerate name" dal menu contestuale (sidebar) e dal menu Workspace: riporta il workspace
    /// a `.default`, azzera abbandono/tentativi/cooldown, nomina **subito** col contesto corrente
    /// saltando le soglie della policy, e riarma il poll come rete di sicurezza.
    ///
    /// Il nome corrente diventa un vincolo ("dammene un altro") solo se l'ha prodotto il modello:
    /// un placeholder o un nome-cartella non sono risposte da evitare, sono contesto o niente.
    func regenerate(_ id: UUID) {
        guard let workspace = store.workspaces.first(where: { $0.id == id }) else { return }
        abandoned.remove(id)
        attempts[id] = nil
        retryAfter[id] = nil
        cleanupTracking(id)
        let avoid = workspace.nameOrigin == .generated ? workspace.name : nil
        store.markNameRegenerable(id)
        nameNow(workspace, avoiding: avoid)
        armEligibilityObserver()
    }

    /// Nomina immediata per l'azione manuale: salta la soglia di stabilità della policy e chiede
    /// subito un nome dal contesto corrente del workspace. A differenza del poll **non tace mai**:
    /// ogni ramo che non produce un nome riporta il perché (`onFailure`), perché qui l'utente ha
    /// chiesto qualcosa e sta aspettando una risposta.
    private func nameNow(_ workspace: Workspace, avoiding: String?) {
        guard settings.workspaceNamingEnabled, let apiKey = credentials.loadKey() else {
            onFailure(workspace.id, .notConfigured)
            return
        }
        guard let prompt = WorkspaceNaming.prompt(
            for: collectSignals(for: workspace), homePath: homePath, avoiding: avoiding
        ) else {
            onFailure(workspace.id, .noContext)
            return
        }
        fire(workspace.id, prompt: prompt, apiKey: apiKey, manual: true)
    }

    /// Osserva **tutte** le tab del workspace, non solo la selezionata: un workspace si nomina da
    /// quello che ci fai, e l'attività può stare in una tab qualsiasi (quella in vista è spesso una
    /// shell ferma mentre l'agente gira accanto). La scelta della tab più informativa e il fallback
    /// alla cartella del workspace sono puri (`WorkspaceNaming.signals`).
    ///
    /// Il costo (due letture di processo per tab) è confinato ai soli workspace ancora `.default`:
    /// quando sono tutti nominati il poll non gira nemmeno.
    private func collectSignals(for workspace: Workspace) -> WorkspaceNameSignals {
        let observed = workspace.tabs.map { tab in
            let agentActive = tab.agentState == .running || tab.agentState == .needsInput
            return TabNamingSignal(
                isVisible: workspace.isVisible(tab.id),
                agent: agentActive ? "claude" : nil,
                command: WorkspaceNaming.command(fromArgv: foregroundCommandLine(tab.id)),
                directory: currentDirectory(tab.id)
            )
        }
        return WorkspaceNaming.signals(from: observed, workspaceRoot: workspace.rootPath)
    }

    // MARK: - Eleggibilità e timer

    /// Si ri-arma sui cambi (Observation): legge `settings.workspaceNamingEnabled` e i `nameOrigin`
    /// dei workspace, così creare un workspace `.default` o cambiare il toggle riaccende/spegne il
    /// timer. La presenza della chiave (non osservabile) è controllata qui e ri-valutata via
    /// `reconfigure()`.
    private func armEligibilityObserver() {
        let eligible = withObservationTracking {
            settings.workspaceNamingEnabled
                && store.workspaces.contains { !$0.archived && $0.nameOrigin == .default }
        } onChange: { [weak self] in
            Task { @MainActor in self?.armEligibilityObserver() }
        }
        if eligible, credentials.hasKey() {
            startTimer()
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let interval = Self.pollInterval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Poll

    private func poll() {
        guard settings.workspaceNamingEnabled, let apiKey = credentials.loadKey() else {
            stopTimer()
            return
        }
        let now = Date()
        prune(to: Set(store.workspaces.map(\.id)))
        let due = store.workspaces.filter {
            isEligible($0) && !isCoolingDown($0.id, now: now)
        }
        for workspace in due {
            evaluate(workspace, apiKey: apiKey, now: now)
        }
    }

    private func isEligible(_ workspace: Workspace) -> Bool {
        !workspace.archived
            && workspace.nameOrigin == .default
            && !abandoned.contains(workspace.id)
            && !inFlight.contains(workspace.id)
    }

    private func isCoolingDown(_ id: UUID, now: Date) -> Bool {
        guard let until = retryAfter[id] else { return false }
        guard now < until else {
            retryAfter[id] = nil
            return false
        }
        return true
    }

    /// Osserva il workspace e delega la decisione alla `NamingTriggerPolicy` pura; se decide di
    /// nominare, fa partire la richiesta. La priorità dei segnali (agente > comando stabile > cwd
    /// stabilizzata) vive nella policy, la scelta della tab da cui leggerli in `collectSignals`.
    private func evaluate(_ workspace: Workspace, apiKey: String, now: Date) {
        let observed = collectSignals(for: workspace)
        var policy = policies[workspace.id] ?? NamingTriggerPolicy()
        let decision = policy.observe(
            agent: observed.agent,
            command: observed.command,
            cwd: observed.directory,
            now: now
        )
        policies[workspace.id] = policy
        guard case let .name(signals) = decision,
              let prompt = WorkspaceNaming.prompt(for: signals, homePath: homePath) else { return }
        fire(workspace.id, prompt: prompt, apiKey: apiKey, manual: false)
    }

    /// Fa partire una richiesta di nomina, se non ce n'è già una in volo per questo workspace (la
    /// seconda produrrebbe comunque un nome: chi arriva dopo non ha niente da aggiungere). Alla
    /// risposta applica il nome ricontrollando che il workspace sia ancora `.default` (l'utente
    /// potrebbe aver rinominato nel frattempo).
    private func fire(
        _ id: UUID,
        prompt: (system: String, user: String),
        apiKey: String,
        manual: Bool
    ) {
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        let baseURL = settings.workspaceNamingBaseURL
        let model = settings.workspaceNamingModel
        Task { [weak self, client] in
            let raw = await client.complete(
                system: prompt.system,
                user: prompt.user,
                apiKey: apiKey,
                baseURL: baseURL,
                model: model
            )
            guard let self else { return }
            inFlight.remove(id)
            guard let raw, let name = WorkspaceNaming.sanitize(raw) else {
                recordFailure(id, manual: manual)
                return
            }
            if store.applyGeneratedName(id, to: name) {
                attempts[id] = nil
                cleanupTracking(id)
                log.info("named workspace: \(name, privacy: .public)")
            }
            // Se non applicato (origine cambiata o workspace sparito): niente da fare, l'ha vinto
            // l'utente.
        }
    }

    /// Un tentativo andato a vuoto: conta, mette il workspace in cooldown (il poll non deve
    /// bruciare i tentativi a raffica) e, per l'azione manuale, lo dice all'utente.
    private func recordFailure(_ id: UUID, manual: Bool) {
        let count = (attempts[id] ?? 0) + 1
        attempts[id] = count
        retryAfter[id] = Date().addingTimeInterval(Self.retryCooldown)
        if count >= Self.maxAttempts {
            abandoned.insert(id)
            cleanupTracking(id)
            log.info("giving up naming workspace after \(count) attempts")
        }
        if manual { onFailure(id, .requestFailed) }
    }

    private func cleanupTracking(_ id: UUID) {
        policies[id] = nil
    }

    /// Toglie lo stato di tracking dei workspace non più esistenti (chiusi), per non accumulare.
    private func prune(to liveIDs: Set<UUID>) {
        attempts = attempts.filter { liveIDs.contains($0.key) }
        abandoned = abandoned.intersection(liveIDs)
        policies = policies.filter { liveIDs.contains($0.key) }
        retryAfter = retryAfter.filter { liveIDs.contains($0.key) }
    }
}
