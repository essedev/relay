import Core
import Foundation
import WorkspaceModel

/// Perché il "Regenerate name" manuale non ha prodotto un nome. La nomina **automatica** resta
/// silenziosa (mai un alert per un nome che non hai chiesto); quella manuale no: un'azione
/// esplicita che non fa niente e non dice niente è indistinguibile da un bug. Il controller non
/// presenta nulla, lo riporta al composition root (unico proprietario dell'UI).
enum NamingFailure: Equatable {
    /// Nomina automatica spenta nelle impostazioni: senza feedback la voce di menu resta muta.
    case notConfigured
    /// Nessun segnale utile: workspace fermo in home, senza comandi in corso né cartella nota.
    case noContext
    /// Senza modello i nomi derivabili sono pochi e deterministici: dal contesto attuale non esce
    /// niente di diverso da come il workspace si chiama già.
    case noAlternative
    /// La richiesta è partita e non ne è uscito un nome (rete, HTTP, parse, sanitize).
    case requestFailed
}

/// Nomina automatica dei workspace. Vive nel composition root (come `UpdateController`): è l'unico
/// punto che tocca la rete per questa feature e lega la logica pura allo store e alle surface. La
/// policy dei trigger (`Core.NamingTriggerPolicy`), la costruzione del prompt, la derivazione
/// locale e la sanitizzazione (`Core.WorkspaceNaming`) stanno nel modulo puro (testato); qui resta
/// il wiring: eleggibilità, timer, letture della surface e rete.
///
/// Modello: un workspace `.default` (placeholder o nome-cartella) è "eleggibile"; un poll leggero
/// osserva **tutte le sue tab** e, al primo segnale utile, produce un nome e lo applica
/// (`applyGeneratedName`, che degrada a no-op se nel frattempo l'utente ha rinominato a mano). Tre
/// segnali, dal più forte: agente attivo (Claude in `running`/`needs_input`) -> subito; comando in
/// foreground stabile (es. `brew update`) -> dopo qualche tick; cwd stabilizzata fuori dalla home
/// -> dopo ~10s. La cwd viene dalla shell **viva** (closure iniettata, precedenza in
/// `Core.CurrentDirectory`), non da `tab.currentDirectory` (solo OSC 7, che zsh in Relay non
/// emette).
///
/// **Chi scrive il nome**: con una API key un modello OpenAI-compatible (single-flight per
/// workspace, max 2 tentativi distanziati da un cooldown, poi si ripiega sul nome derivato); senza,
/// direttamente `WorkspaceNaming.localNames` - nessuna rete, nessuna attesa. I trigger sono gli
/// stessi: la chiave cambia la qualità del nome, non il comportamento della feature.
///
/// "Regenerate name" (`regenerate`) è l'azione **manuale**: nomina subito col contesto corrente
/// saltando le soglie della policy, chiede un nome **diverso** da quello attuale e, se non ce la
/// fa, lo dice (`onFailure` -> alert nel composition root). Il poll resta la rete di sicurezza per
/// il prossimo segnale.
///
/// Lazy: il timer di poll esiste **solo** quando la nomina è accesa e c'è almeno un workspace
/// `.default` da nominare (osservazione su `nameOrigin`); quando tutti sono nominati il timer si
/// ferma da solo. Il poll è comunque a costo trascurabile (un filtro su pochi workspace ogni pochi
/// secondi), fuori dal path caldo del terminale.
@MainActor
final class NamingController {
    let store: WorkspaceStore
    let settings: AppSettings
    let credentials: NamingCredentialStore
    /// Chiamata all'endpoint OpenAI-compatible (`ChatCompletionClient`): qui si decide *quando*
    /// chiedere un nome, lì *come* si chiede.
    let client: ChatCompletionClient
    let homePath: String
    /// Argv del processo in foreground di una tab (iniettata: raggiunge lo split -> registry).
    let foregroundCommandLine: (UUID) -> [String]?
    /// Cwd migliore nota per una tab (iniettata: `WorkspaceAreaController.currentDirectory`, con la
    /// precedenza shell viva -> ultimo OSC 7 -> root). **Non** `tab.currentDirectory`: quello è il
    /// solo OSC 7, che zsh in Relay non emette (vedi gotcha OSC 7), quindi il segnale cwd sarebbe
    /// sempre nil e la nomina da directory non scatterebbe mai.
    let currentDirectory: (UUID) -> String?
    /// Feedback dell'azione manuale verso il composition root (che possiede l'UI). Il poll non la
    /// usa mai: la nomina automatica è silenziosa per design.
    let onFailure: (UUID, NamingFailure) -> Void
    let log = RelayLog.logger("naming")

    /// Intervallo del poll. Un compromesso: abbastanza reattivo per cogliere un `brew update` senza
    /// spammare. La latenza di nomina non è UX critica.
    static let pollInterval: TimeInterval = 3
    /// Tentativi per workspace prima di arrendersi (errori di rete/parse/sanitize).
    static let maxAttempts = 2
    /// Pausa dopo un tentativo fallito. Senza, la policy che ha già deciso "nomina" ridecide a ogni
    /// tick e i tentativi si bruciano in sei secondi: un singolo blip di rete spegneva la nomina
    /// del workspace per sempre.
    static let retryCooldown: TimeInterval = 60

    var timer: Timer?
    /// Richieste in volo per workspace (single-flight): non ne parte una seconda finché la prima
    /// non torna.
    var inFlight: Set<UUID> = []
    /// Tentativi falliti per workspace; raggiunta la soglia il workspace entra in `abandoned`.
    var attempts: [UUID: Int] = [:]
    /// Workspace per cui abbiamo smesso di provare (max tentativi): saltati dal poll.
    var abandoned: Set<UUID> = []
    /// Fine del cooldown post-fallimento per workspace: il poll li salta fino a quel momento.
    /// L'azione manuale lo ignora (è una richiesta esplicita) e lo azzera.
    var retryAfter: [UUID: Date] = [:]
    /// "Regenerate name" arrivato mentre una richiesta era già in volo (tipicamente una del poll,
    /// partita un attimo prima). Si rimanda alla fine di quella invece di scartarlo: scartandolo
    /// l'azione manuale sarebbe muta, e il nome che sta per arrivare è quello del poll, calcolato
    /// **senza** `avoiding`, cioè - a `temperature` 0 - identico a quello che c'è già.
    var queuedRegenerate: Set<UUID> = []
    /// API key in cache. Rileggerla dal disco a ogni tick (ogni 3s, finché esiste un workspace
    /// `.default`) è I/O inutile: si ricarica quando l'eleggibilità viene ri-valutata, cioè anche a
    /// ogni `reconfigure()` (che le impostazioni chiamano quando la chiave viene salvata).
    var apiKey: String?
    /// Generazione dell'osservatore di eleggibilità. `withObservationTracking` non si disdice, e
    /// ogni ri-arma (start, reconfigure, regenerate, cambio osservato) ne lascia in giro uno
    /// vecchio che allo scatto successivo rifarebbe tutto il giro in parallelo. Chi scatta con una
    /// generazione superata si estingue in silenzio.
    var observerGeneration = 0
    /// Policy dei trigger per workspace (streak comando + stabilizzazione cwd). Logica pura in
    /// `Core.NamingTriggerPolicy`; qui resta solo lo stato accumulato tick dopo tick.
    var policies: [UUID: NamingTriggerPolicy] = [:]

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

    /// "Regenerate name" dal menu contestuale (sidebar) e dal menu Workspace: nomina **subito** col
    /// contesto corrente saltando le soglie della policy, riporta il workspace a `.default`, azzera
    /// abbandono/tentativi/cooldown e riarma il poll come rete di sicurezza.
    ///
    /// Il nome corrente diventa un vincolo ("dammene un altro") solo se l'ha prodotto il modello:
    /// un placeholder o un nome-cartella non sono risposte da evitare, sono contesto o niente.
    ///
    /// **Non tace mai**: ogni ramo che non porta a una richiesta o dice perché (`onFailure`) o la
    /// mette in coda. Mentre la richiesta è in volo il nome pulsa in sidebar (`store.setNaming`).
    func regenerate(_ id: UUID) {
        guard let workspace = store.workspaces.first(where: { $0.id == id }) else { return }
        // Prima le guardie, poi il declassamento: un `.user` non deve perdere la sua immunità per
        // un tentativo che non è nemmeno partito (feature spenta, nessun contesto).
        guard settings.workspaceNamingEnabled else {
            onFailure(id, .notConfigured)
            return
        }
        let signals = collectSignals(for: workspace)
        guard let key = resolvedAPIKey() else {
            regenerateLocally(workspace, signals: signals)
            return
        }
        // Il nome corrente diventa un vincolo solo se l'ha prodotto il modello.
        let avoid = workspace.nameOrigin == .generated ? workspace.name : nil
        guard let prompt = WorkspaceNaming.prompt(
            for: signals, homePath: homePath, avoiding: avoid
        ) else {
            onFailure(id, .noContext)
            return
        }
        // C'è già una richiesta per questo workspace: la seconda non partirebbe (single-flight), e
        // uscire di soppiatto renderebbe muta l'azione manuale. La si rimanda alla fine di quella.
        guard !inFlight.contains(id) else {
            queuedRegenerate.insert(id)
            return
        }
        resetTracking(id)
        store.markNameRegenerable(id)
        fire(id, signals: signals, prompt: prompt, apiKey: key, manual: true)
        armEligibilityObserver()
    }

    /// Regenerate senza modello: si prende il primo nome derivabile **diverso** da quello attuale.
    /// La derivazione è deterministica, quindi qui l'alternativa o esiste (di solito il comando in
    /// corso, quando il nome attuale viene dalla cartella) o non esiste affatto: dirlo è meglio che
    /// riapplicare lo stesso nome e sembrare rotti.
    func regenerateLocally(_ workspace: Workspace, signals: WorkspaceNameSignals) {
        let candidates = WorkspaceNaming.localNames(for: signals, homePath: homePath)
        guard !candidates.isEmpty else {
            onFailure(workspace.id, .noContext)
            return
        }
        let current = workspace.name.lowercased()
        guard let name = candidates.first(where: { $0.lowercased() != current }) else {
            onFailure(workspace.id, .noAlternative)
            return
        }
        resetTracking(workspace.id)
        store.markNameRegenerable(workspace.id)
        store.applyGeneratedName(workspace.id, to: name)
        armEligibilityObserver()
    }

    /// Riapre la partita su un workspace: dimentica abbandono, tentativi, cooldown e stato della
    /// policy. È quel che serve perché un'azione esplicita non erediti la storia dei fallimenti.
    func resetTracking(_ id: UUID) {
        abandoned.remove(id)
        attempts[id] = nil
        retryAfter[id] = nil
        cleanupTracking(id)
    }

    /// Osserva **tutte** le tab del workspace, non solo la selezionata: un workspace si nomina da
    /// quello che ci fai, e l'attività può stare in una tab qualsiasi (quella in vista è spesso una
    /// shell ferma mentre l'agente gira accanto). La scelta della tab più informativa e il fallback
    /// alla cartella del workspace sono puri (`WorkspaceNaming.signals`).
    ///
    /// Il costo (due letture di processo per tab) è confinato ai soli workspace ancora `.default`:
    /// quando sono tutti nominati il poll non gira nemmeno.
    func collectSignals(for workspace: Workspace) -> WorkspaceNameSignals {
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

    /// Applica il nome derivato senza modello. Ritorna `false` se dai segnali non esce niente
    /// (allora il workspace resta eleggibile: al prossimo `cd` o comando ci si riprova).
    @discardableResult
    func applyLocalName(_ id: UUID, signals: WorkspaceNameSignals) -> Bool {
        guard let name = WorkspaceNaming.localNames(for: signals, homePath: homePath).first,
              store.applyGeneratedName(id, to: name) else { return false }
        cleanupTracking(id)
        log.info("named workspace locally: \(name, privacy: .public)")
        return true
    }

    /// Fa partire una richiesta di nomina, se non ce n'è già una in volo per questo workspace (la
    /// seconda produrrebbe comunque un nome: chi arriva dopo non ha niente da aggiungere). Alla
    /// risposta applica il nome ricontrollando che il workspace sia ancora `.default` (l'utente
    /// potrebbe aver rinominato nel frattempo).
    func fire(
        _ id: UUID,
        signals: WorkspaceNameSignals,
        prompt: (system: String, user: String),
        apiKey: String,
        manual: Bool
    ) {
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        // Segnale di lavoro in corso: il nome pulsa in sidebar. Vale anche per il poll - una nomina
        // che arriva da sola è meno spaesante se si è visto che stava succedendo.
        store.setNaming(id, true)
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
            store.setNaming(id, false)
            defer { drainQueuedRegenerate(id) }
            guard let raw, let name = WorkspaceNaming.sanitize(raw) else {
                recordFailure(id, signals: signals, manual: manual)
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

    /// Esegue il "Regenerate name" che era arrivato mentre la richiesta precedente era in volo. Ora
    /// il contesto è quello di adesso e il nome da evitare è quello appena applicato: è la stessa
    /// cosa che l'utente otterrebbe premendo di nuovo la voce di menu, senza doverlo fare.
    func drainQueuedRegenerate(_ id: UUID) {
        guard queuedRegenerate.remove(id) != nil else { return }
        regenerate(id)
    }

    /// Un tentativo andato a vuoto: conta, mette il workspace in cooldown (il poll non deve
    /// bruciare i tentativi a raffica) e, per l'azione manuale, lo dice all'utente.
    ///
    /// Esauriti i tentativi non si molla in silenzio: si ripiega sul nome derivato dai segnali.
    /// Peggiore di quello del modello, incomparabilmente meglio di "Workspace 3" per sempre. Se il
    /// ripiego ha nominato, l'azione manuale non mostra l'errore: un nome è arrivato.
    func recordFailure(_ id: UUID, signals: WorkspaceNameSignals, manual: Bool) {
        let count = (attempts[id] ?? 0) + 1
        attempts[id] = count
        retryAfter[id] = Date().addingTimeInterval(Self.retryCooldown)
        var salvaged = false
        if count >= Self.maxAttempts {
            salvaged = applyLocalName(id, signals: signals)
            if !salvaged { abandoned.insert(id) }
            cleanupTracking(id)
            log.info("giving up on the model after \(count) attempts (local name: \(salvaged))")
        }
        if manual, !salvaged { onFailure(id, .requestFailed) }
    }

    func cleanupTracking(_ id: UUID) {
        policies[id] = nil
    }

    /// Toglie lo stato di tracking dei workspace non più esistenti (chiusi), per non accumulare.
    func prune(to liveIDs: Set<UUID>) {
        attempts = attempts.filter { liveIDs.contains($0.key) }
        abandoned = abandoned.intersection(liveIDs)
        policies = policies.filter { liveIDs.contains($0.key) }
        retryAfter = retryAfter.filter { liveIDs.contains($0.key) }
    }
}
