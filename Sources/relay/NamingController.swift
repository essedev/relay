import AppKit
import Core
import Foundation
import WorkspaceModel

/// Nomina automatica dei workspace via LLM (endpoint OpenAI-compatible). Vive nel composition root
/// (come `UpdateController`): è l'unico punto che tocca la rete per questa feature e lega la logica
/// pura (`Core.WorkspaceNaming`) allo store e alle surface. La policy dei trigger sta qui, la
/// costruzione del prompt e la sanitizzazione nel modulo puro (testato).
///
/// Modello: un workspace `.default` (placeholder o nome-cartella) è "eleggibile"; un poll leggero
/// osserva la sua tab selezionata e, al primo segnale utile, chiede un nome e lo applica
/// (`applyGeneratedName`, che degrada a no-op se nel frattempo l'utente ha rinominato a mano). Tre
/// segnali, dal più forte: agente attivo (Claude in `running`/`needs_input`) -> subito; comando in
/// foreground stabile (es. `brew update`) -> dopo qualche tick; cwd stabilizzata fuori dalla home
/// -> dopo ~10s. Single-flight per workspace, max 2 tentativi poi si arrende in silenzio.
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
    private let session: URLSession
    private let homePath: String
    /// Argv del processo in foreground di una tab (iniettata: raggiunge lo split -> registry).
    private let foregroundCommandLine: (UUID) -> [String]?
    private let log = RelayLog.logger("naming")

    /// Intervallo del poll. Un compromesso: abbastanza reattivo per cogliere un `brew update` senza
    /// spammare. La latenza di nomina non è UX critica.
    private static let pollInterval: TimeInterval = 3
    /// Secondi di cwd stabile (immutata) prima di nominare dalla sola directory.
    private static let cwdStableSeconds: TimeInterval = 10
    /// Tick consecutivi con lo stesso comando in foreground prima di nominare da esso (filtra i
    /// comandi lampo come un `ls`).
    private static let commandStreakThreshold = 2
    /// Tentativi per workspace prima di arrendersi (errori di rete/parse/sanitize).
    private static let maxAttempts = 2

    private var timer: Timer?
    /// Richieste in volo per workspace (single-flight): non ne parte una seconda finché la prima
    /// non torna.
    private var inFlight: Set<UUID> = []
    /// Tentativi falliti per workspace; raggiunta la soglia il workspace entra in `abandoned`.
    private var attempts: [UUID: Int] = [:]
    /// Workspace per cui abbiamo smesso di provare (max tentativi): saltati dal poll.
    private var abandoned: Set<UUID> = []
    /// Streak del comando in foreground per workspace (comando + tick consecutivi).
    private var commandStreak: [UUID: (command: String, count: Int)] = [:]
    /// Tracking della cwd per la stabilizzazione (path corrente + da quando è stabile).
    private var cwdTracking: [UUID: (path: String, since: Date)] = [:]

    init(
        store: WorkspaceStore,
        settings: AppSettings,
        credentials: NamingCredentialStore,
        foregroundCommandLine: @escaping (UUID) -> [String]?,
        session: URLSession = .shared,
        homePath: String = NSHomeDirectory()
    ) {
        self.store = store
        self.settings = settings
        self.credentials = credentials
        self.foregroundCommandLine = foregroundCommandLine
        self.session = session
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

    /// "Regenerate name" dal menu contestuale: riporta il workspace a `.default`, azzera lo stato
    /// di
    /// abbandono/tentativi e riavvia il poll così viene rinominato al prossimo segnale.
    func regenerate(_ id: UUID) {
        abandoned.remove(id)
        attempts[id] = nil
        cleanupTracking(id)
        store.markNameRegenerable(id)
        armEligibilityObserver()
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
        for workspace in store.workspaces where isEligible(workspace) {
            evaluate(workspace, apiKey: apiKey, now: now)
        }
    }

    private func isEligible(_ workspace: Workspace) -> Bool {
        !workspace.archived
            && workspace.nameOrigin == .default
            && !abandoned.contains(workspace.id)
            && !inFlight.contains(workspace.id)
    }

    /// Valuta la tab selezionata di un workspace eleggibile e, al primo segnale utile, fa partire
    /// la
    /// nomina. Priorità: agente attivo (subito) > comando stabile > cwd stabilizzata.
    private func evaluate(_ workspace: Workspace, apiKey: String, now: Date) {
        guard let tab = workspace.selectedTab else { return }
        let cwd = tab.currentDirectory
        let agentActive = tab.agentState == .running || tab.agentState == .needsInput
        let command = WorkspaceNaming.command(fromArgv: foregroundCommandLine(tab.id))

        // 1) Agente attivo: segnale forte, nomina subito (cwd + eventuale comando + agente).
        if agentActive {
            fire(
                workspace.id,
                signals: WorkspaceNameSignals(directory: cwd, command: command, agent: "claude"),
                apiKey: apiKey
            )
            return
        }

        // 2) Comando in foreground stabile per N tick consecutivi (filtra i comandi lampo).
        if let command {
            let previous = commandStreak[workspace.id]
            let streak = (previous?.command == command ? (previous?.count ?? 0) : 0) + 1
            commandStreak[workspace.id] = (command, streak)
            if streak >= Self.commandStreakThreshold {
                fire(
                    workspace.id,
                    signals: WorkspaceNameSignals(directory: cwd, command: command),
                    apiKey: apiKey
                )
                return
            }
        } else {
            commandStreak[workspace.id] = nil
        }

        // 3) cwd stabile (immutata da >= cwdStableSeconds) e fuori dalla home. `fire` scarta da
        // solo
        // il caso non azionabile (prompt nil), quindi una cwd = home non fa partire niente.
        if let cwd {
            if cwdTracking[workspace.id]?.path != cwd {
                cwdTracking[workspace.id] = (cwd, now)
            } else if cwdStable(workspace.id, now: now) {
                fire(workspace.id, signals: WorkspaceNameSignals(directory: cwd), apiKey: apiKey)
            }
        }
    }

    /// `true` se la cwd tracciata per il workspace è stabile da almeno `cwdStableSeconds`.
    private func cwdStable(_ id: UUID, now: Date) -> Bool {
        guard let since = cwdTracking[id]?.since else { return false }
        return now.timeIntervalSince(since) >= Self.cwdStableSeconds
    }

    /// Fa partire una richiesta di nomina se i segnali sono azionabili (`prompt != nil`) e non ce
    /// n'è già una in volo per questo workspace. Alla risposta applica il nome ricontrollando che
    /// il
    /// workspace sia ancora `.default` (l'utente potrebbe aver rinominato nel frattempo).
    private func fire(_ id: UUID, signals: WorkspaceNameSignals, apiKey: String) {
        guard !inFlight.contains(id),
              let prompt = WorkspaceNaming.prompt(for: signals, homePath: homePath) else { return }
        inFlight.insert(id)
        let baseURL = settings.workspaceNamingBaseURL
        let model = settings.workspaceNamingModel
        Task { [weak self] in
            let raw = await self?.requestName(
                prompt: prompt, apiKey: apiKey, baseURL: baseURL, model: model
            )
            guard let self else { return }
            inFlight.remove(id)
            guard let raw, let name = WorkspaceNaming.sanitize(raw) else {
                recordFailure(id)
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

    private func recordFailure(_ id: UUID) {
        let count = (attempts[id] ?? 0) + 1
        attempts[id] = count
        if count >= Self.maxAttempts {
            abandoned.insert(id)
            cleanupTracking(id)
            log.info("giving up naming workspace after \(count) attempts")
        }
    }

    private func cleanupTracking(_ id: UUID) {
        commandStreak[id] = nil
        cwdTracking[id] = nil
    }

    /// Toglie lo stato di tracking dei workspace non più esistenti (chiusi), per non accumulare.
    private func prune(to liveIDs: Set<UUID>) {
        attempts = attempts.filter { liveIDs.contains($0.key) }
        abandoned = abandoned.intersection(liveIDs)
        commandStreak = commandStreak.filter { liveIDs.contains($0.key) }
        cwdTracking = cwdTracking.filter { liveIDs.contains($0.key) }
    }

    // MARK: - Rete

    /// Chiede un nome all'endpoint OpenAI-compatible (`/chat/completions`). Ritorna il contenuto
    /// grezzo del modello, o `nil` su qualunque errore (rete, HTTP != 200, JSON, timeout 10s). La
    /// sanitizzazione la fa il chiamante col puro `WorkspaceNaming`.
    private func requestName(
        prompt: (system: String, user: String),
        apiKey: String,
        baseURL: String,
        model: String
    ) async -> String? {
        guard let url = chatCompletionsURL(from: baseURL) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: prompt.system),
                .init(role: "user", content: prompt.user),
            ],
            temperature: 0,
            maxTokens: 16
        )
        guard let payload = try? JSONEncoder().encode(body) else { return nil }
        request.httpBody = payload
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                log.error("naming request: bad response")
                return nil
            }
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            return decoded.choices.first?.message.content
        } catch {
            log.error("naming request failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Compone l'URL `/chat/completions` dalla base, tollerando un eventuale trailing slash.
    private func chatCompletionsURL(from baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return URL(string: base + "/chat/completions")
    }
}

// MARK: - Payload OpenAI-compatible

private struct ChatRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let maxTokens: Int

    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}
