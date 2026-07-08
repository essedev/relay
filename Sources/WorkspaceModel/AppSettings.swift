import Core
import Foundation

/// Preferenze estetiche dell'app (tema, dimensione font), osservabili e persistite in
/// `UserDefaults`. Distinte dallo snapshot del layout (Milestone 2): qui vivono le *preferenze*,
/// il posto giusto per UserDefaults. Sia il terminale sia la chrome derivano da `theme`.
@MainActor
@Observable
public final class AppSettings {
    public static let minFontSize: Double = 9
    public static let maxFontSize: Double = 28
    public static let defaultSidebarWidth: Double = 250
    /// Decadenza dei sospesi attiva di default: un promemoria quieto che non tocchi per mezza
    /// giornata è rumore (banner blindness). Deve stare tra le `pendingDecayOptions`.
    public static let defaultPendingDecayHours = 12
    public static let minSidebarWidth: Double = 200
    public static let maxSidebarWidth: Double = 340

    public private(set) var themeName: String
    public private(set) var fontSize: Double
    /// Font family del terminale; `nil` = monospace di sistema (SF Mono). Sovrascrive il `fontName`
    /// del tema, come `fontSize`.
    public private(set) var fontName: String?
    public private(set) var cursorBlink: Bool
    public private(set) var sidebarCollapsed: Bool
    /// Sezione Archive in fondo alla sidebar espansa (mostra i workspace archiviati) o collassata.
    /// Default collassata: l'archivio è "messo via". Preferenza UI, non layout.
    public private(set) var archiveExpanded: Bool
    /// Larghezza della sidebar in punti (clampata a `min/maxSidebarWidth`), persistita: l'utente la
    /// ridimensiona e resta tra i riavvii. Preferenza UI globale, non layout per-workspace.
    public private(set) var sidebarWidth: Double
    /// Al re-focus di una tab ripristinata con sessione agente: `true` inietta il resume da solo,
    /// `false` (default) mostra la barra "Resume". Default prudente: niente comandi automatici.
    public private(set) var autoResumeAgents: Bool
    /// Decadenza dei completamenti "in sospeso" (`AttentionLevel.pending`): dopo queste ore il
    /// marker si spegne da solo. Default `defaultPendingDecayHours` (12h): il sospeso è il segnale
    /// *quieto* e già visto, tenerlo per sempre è banner blindness. `0` = mai (opt-out esplicito):
    /// il segnale forte `unseen` resta comunque intatto, non scade mai da solo.
    public private(set) var pendingDecayHours: Int

    /// Notifiche macOS (default tutte on). Master + per-tipo + suono + scelta del suono.
    public private(set) var notificationsEnabled: Bool
    public private(set) var notifyOnNeedsInput: Bool
    public private(set) var notifyOnCompleted: Bool
    public private(set) var notificationSound: Bool
    public private(set) var notificationSoundName: String

    /// Check aggiornamenti (default on): al lancio l'app confronta la versione installata con
    /// l'ultima release. `skippedUpdateVersion` è la versione che l'utente ha scelto di ignorare
    /// (si torna a proporre solo quando ne esce una più nuova).
    public private(set) var checkForUpdatesAutomatically: Bool
    public private(set) var skippedUpdateVersion: String?

    /// Onboarding (Welcome to Relay) già mostrato: al primo avvio l'overlay parte da solo, poi si
    /// riapre solo da Help > Welcome to Relay. One-shot, non torna `false`.
    public private(set) var onboardingSeen: Bool

    /// Nomina automatica dei workspace via LLM (endpoint OpenAI-compatible). `enabled` di default
    /// on, ma la feature resta **inerte senza una API key** (salvata a parte, file 0600): serve
    /// solo a spegnerla anche con la chiave presente. `baseURL`/`model` puntano all'endpoint;
    /// niente segreti qui (la chiave sta nel `NamingCredentialStore` nel composition root).
    public private(set) var workspaceNamingEnabled: Bool
    public private(set) var workspaceNamingBaseURL: String
    public private(set) var workspaceNamingModel: String

    public static let defaultNamingBaseURL = "https://api.openai.com/v1"
    public static let defaultNamingModel = "gpt-4o-mini"

    /// Combinazioni per le azioni rimappabili. Dizionario completo (ogni `ShortcutAction`), che
    /// parte dai default e sovrascrive con quanto salvato. I select-by-number e i comandi di
    /// sistema non sono rimappabili e non stanno qui.
    public private(set) var keybindings: [ShortcutAction: KeyCombo]

    /// Vero mentre il recorder cattura una combinazione: il monitor globale si fa da parte (non
    /// esegue azioni né mark-read), così l'evento arriva al recorder. Transitorio, non persistito.
    @ObservationIgnored public var isCapturingShortcut = false

    /// Suoni di notifica selezionabili (nomi dei classici alert di sistema, `.aiff`). "Default" usa
    /// il suono di notifica di sistema.
    public static let availableSounds = [
        "Default", "Ping", "Glass", "Hero", "Submarine", "Funk", "Blow", "Pop",
    ]

    /// Opzioni di decadenza dei sospesi, in ore (`0` = mai).
    public static let pendingDecayOptions = [0, 4, 12, 24]

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        themeName = defaults.string(forKey: Keys.themeName) ?? RelayTheme.relayDark.name
        let savedSize = defaults.double(forKey: Keys.fontSize)
        fontSize = savedSize == 0 ? RelayTheme.relayDark.fontSize : savedSize
        fontName = defaults.string(forKey: Keys.fontName)
        // Assente = false = caret fisso: il default di prodotto è niente blink.
        cursorBlink = defaults.bool(forKey: Keys.cursorBlink)
        sidebarCollapsed = defaults.bool(forKey: Keys.sidebarCollapsed)
        archiveExpanded = defaults.bool(forKey: Keys.archiveExpanded)
        // Assente = 0 = usa il default (double(forKey:) torna 0 per chiave mancante).
        let savedSidebarWidth = defaults.double(forKey: Keys.sidebarWidth)
        sidebarWidth = savedSidebarWidth == 0 ? Self.defaultSidebarWidth : savedSidebarWidth
        autoResumeAgents = defaults.bool(forKey: Keys.autoResumeAgents)
        // Chiave assente -> default attivo (12h); un `0` salvato (opt-out esplicito) va rispettato,
        // quindi distinguo "mai scritto" da "scritto 0" (integer(forKey:) torna 0 in entrambi).
        pendingDecayHours = defaults.object(forKey: Keys.pendingDecayHours) == nil
            ? Self.defaultPendingDecayHours
            : defaults.integer(forKey: Keys.pendingDecayHours)
        notificationsEnabled = Self.boolDefaultingTrue(defaults, Keys.notificationsEnabled)
        notifyOnNeedsInput = Self.boolDefaultingTrue(defaults, Keys.notifyOnNeedsInput)
        notifyOnCompleted = Self.boolDefaultingTrue(defaults, Keys.notifyOnCompleted)
        notificationSound = Self.boolDefaultingTrue(defaults, Keys.notificationSound)
        notificationSoundName = defaults.string(forKey: Keys.notificationSoundName) ?? "Default"
        checkForUpdatesAutomatically = Self.boolDefaultingTrue(defaults, Keys.checkForUpdates)
        skippedUpdateVersion = defaults.string(forKey: Keys.skippedUpdateVersion)
        onboardingSeen = defaults.bool(forKey: Keys.onboardingSeen)
        workspaceNamingEnabled = Self.boolDefaultingTrue(defaults, Keys.workspaceNamingEnabled)
        workspaceNamingBaseURL = defaults.string(forKey: Keys.workspaceNamingBaseURL)
            ?? Self.defaultNamingBaseURL
        workspaceNamingModel = defaults.string(forKey: Keys.workspaceNamingModel)
            ?? Self.defaultNamingModel
        keybindings = Self.loadKeybindings(defaults)
    }

    /// Parte dai default e sovrascrive con le combo salvate (per rawValue), ignorando azioni non
    /// più esistenti: così aggiungere una nuova azione non richiede migrazioni.
    private static func loadKeybindings(_ defaults: UserDefaults) -> [ShortcutAction: KeyCombo] {
        var result: [ShortcutAction: KeyCombo] = [:]
        for action in ShortcutAction.allCases {
            result[action] = action.defaultCombo
        }
        guard let data = defaults.data(forKey: Keys.keybindings),
              let saved = try? JSONDecoder().decode([String: KeyCombo].self, from: data)
        else { return result }
        for (raw, combo) in saved {
            if let action = ShortcutAction(rawValue: raw) { result[action] = combo }
        }
        return result
    }

    /// Bool con default `true` quando la chiave è assente (UserDefaults.bool darebbe `false`).
    private static func boolDefaultingTrue(_ defaults: UserDefaults, _ key: String) -> Bool {
        defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    /// Temi selezionabili (per il picker delle impostazioni).
    public var availableThemes: [RelayTheme] {
        RelayTheme.all
    }

    /// Tema effettivo: quello scelto, con font family/size e blink del caret correnti sovrapposti.
    public var theme: RelayTheme {
        let base = RelayTheme.all.first { $0.name == themeName } ?? .relayDark
        return base.withFontSize(fontSize).withCursorBlink(cursorBlink).withFontName(fontName)
    }

    public func selectTheme(_ name: String) {
        guard RelayTheme.all.contains(where: { $0.name == name }) else { return }
        themeName = name
        persist()
    }

    public func setFontSize(_ size: Double) {
        let clamped = min(max(size, Self.minFontSize), Self.maxFontSize)
        guard clamped != fontSize else { return }
        fontSize = clamped
        persist()
    }

    public func adjustFontSize(by delta: Double) {
        setFontSize(fontSize + delta)
    }

    public func resetFontSize() {
        setFontSize(RelayTheme.relayDark.fontSize)
    }

    /// Sceglie il font family del terminale; `nil` (o vuoto) torna al monospace di sistema.
    public func setFontName(_ name: String?) {
        let normalized = name?.trimmingCharacters(in: .whitespaces)
        let value = (normalized?.isEmpty ?? true) ? nil : normalized
        guard value != fontName else { return }
        fontName = value
        if let value {
            defaults.set(value, forKey: Keys.fontName)
        } else {
            defaults.removeObject(forKey: Keys.fontName)
        }
    }

    public func setCursorBlink(_ enabled: Bool) {
        guard enabled != cursorBlink else { return }
        cursorBlink = enabled
        defaults.set(cursorBlink, forKey: Keys.cursorBlink)
    }

    public func toggleSidebar() {
        sidebarCollapsed.toggle()
        defaults.set(sidebarCollapsed, forKey: Keys.sidebarCollapsed)
    }

    public func toggleArchiveExpanded() {
        archiveExpanded.toggle()
        defaults.set(archiveExpanded, forKey: Keys.archiveExpanded)
    }

    public func setSidebarWidth(_ width: Double) {
        let clamped = min(max(width, Self.minSidebarWidth), Self.maxSidebarWidth)
        guard clamped != sidebarWidth else { return }
        sidebarWidth = clamped
        defaults.set(clamped, forKey: Keys.sidebarWidth)
    }

    public func setAutoResumeAgents(_ enabled: Bool) {
        guard enabled != autoResumeAgents else { return }
        autoResumeAgents = enabled
        defaults.set(autoResumeAgents, forKey: Keys.autoResumeAgents)
    }

    public func setPendingDecayHours(_ hours: Int) {
        let clamped = max(0, hours)
        guard clamped != pendingDecayHours else { return }
        pendingDecayHours = clamped
        defaults.set(clamped, forKey: Keys.pendingDecayHours)
    }

    public func setCheckForUpdatesAutomatically(_ enabled: Bool) {
        guard enabled != checkForUpdatesAutomatically else { return }
        checkForUpdatesAutomatically = enabled
        defaults.set(enabled, forKey: Keys.checkForUpdates)
    }

    /// Timbra l'onboarding come visto (alla prima presentazione): non ripartirà da solo.
    public func markOnboardingSeen() {
        guard !onboardingSeen else { return }
        onboardingSeen = true
        defaults.set(true, forKey: Keys.onboardingSeen)
    }

    /// Mette in "skip" una versione: non verrà più proposta finché non ne esce una più nuova.
    public func skipUpdateVersion(_ version: String) {
        guard version != skippedUpdateVersion else { return }
        skippedUpdateVersion = version
        defaults.set(version, forKey: Keys.skippedUpdateVersion)
    }

    public func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled != notificationsEnabled else { return }
        notificationsEnabled = enabled
        defaults.set(enabled, forKey: Keys.notificationsEnabled)
    }

    public func setNotifyOnNeedsInput(_ enabled: Bool) {
        guard enabled != notifyOnNeedsInput else { return }
        notifyOnNeedsInput = enabled
        defaults.set(enabled, forKey: Keys.notifyOnNeedsInput)
    }

    public func setNotifyOnCompleted(_ enabled: Bool) {
        guard enabled != notifyOnCompleted else { return }
        notifyOnCompleted = enabled
        defaults.set(enabled, forKey: Keys.notifyOnCompleted)
    }

    public func setNotificationSound(_ enabled: Bool) {
        guard enabled != notificationSound else { return }
        notificationSound = enabled
        defaults.set(enabled, forKey: Keys.notificationSound)
    }

    public func setNotificationSoundName(_ name: String) {
        guard name != notificationSoundName else { return }
        notificationSoundName = name
        defaults.set(name, forKey: Keys.notificationSoundName)
    }

    // MARK: - Keybindings

    /// La combinazione per l'azione (default se non rimappata).
    public func binding(for action: ShortcutAction) -> KeyCombo {
        keybindings[action] ?? action.defaultCombo
    }

    public func setBinding(_ combo: KeyCombo, for action: ShortcutAction) {
        guard keybindings[action] != combo else { return }
        keybindings[action] = combo
        persistKeybindings()
    }

    public func resetBinding(for action: ShortcutAction) {
        setBinding(action.defaultCombo, for: action)
    }

    public func resetAllShortcuts() {
        for action in ShortcutAction.allCases {
            keybindings[action] = action.defaultCombo
        }
        persistKeybindings()
    }

    /// Azione (diversa da `excluding`) che usa già `combo`: per segnalare un conflitto in UI.
    public func conflict(for combo: KeyCombo, excluding: ShortcutAction) -> ShortcutAction? {
        keybindings.first { $0.key != excluding && $0.value == combo }?.key
    }

    private func persistKeybindings() {
        // Persisti solo i binding diversi dal default: `loadKeybindings` parte dai default e
        // sovrappone i salvati, quindi le azioni non rimappate continuano a seguire il default
        // shippato (che una versione futura può cambiare, es. per un conflitto con una nuova
        // azione).
        // Salvare l'intero dizionario congelerebbe i vecchi default per chi tocca anche una sola
        // scorciatoia.
        let overrides = keybindings.filter { $0.value != $0.key.defaultCombo }
        let raw = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Keys.keybindings)
        }
    }

    private func persist() {
        defaults.set(themeName, forKey: Keys.themeName)
        defaults.set(fontSize, forKey: Keys.fontSize)
    }

    private enum Keys {
        static let themeName = "relay.theme.name"
        static let fontSize = "relay.theme.fontSize"
        static let fontName = "relay.theme.fontName"
        static let cursorBlink = "relay.cursor.blink"
        static let sidebarCollapsed = "relay.sidebar.collapsed"
        static let archiveExpanded = "relay.sidebar.archiveExpanded"
        static let sidebarWidth = "relay.sidebar.width"
        static let autoResumeAgents = "relay.agents.autoResume"
        static let pendingDecayHours = "relay.agents.pendingDecayHours"
        static let notificationsEnabled = "relay.notifications.enabled"
        static let notifyOnNeedsInput = "relay.notifications.needsInput"
        static let notifyOnCompleted = "relay.notifications.completed"
        static let notificationSound = "relay.notifications.sound"
        static let notificationSoundName = "relay.notifications.soundName"
        static let checkForUpdates = "relay.updates.checkAutomatically"
        static let skippedUpdateVersion = "relay.updates.skippedVersion"
        static let onboardingSeen = "relay.onboarding.seen"
        static let workspaceNamingEnabled = "relay.naming.enabled"
        static let workspaceNamingBaseURL = "relay.naming.baseURL"
        static let workspaceNamingModel = "relay.naming.model"
        static let keybindings = "relay.shortcuts.bindings"
    }
}

// MARK: - Nomina automatica workspace

/// Setter della nomina automatica, in extension nello stesso file: fuori dal corpo del tipo (il
/// budget `type_body_length`), ma con accesso a `defaults`/`Keys` privati (stesso file).
public extension AppSettings {
    func setWorkspaceNamingEnabled(_ enabled: Bool) {
        guard enabled != workspaceNamingEnabled else { return }
        workspaceNamingEnabled = enabled
        defaults.set(enabled, forKey: Keys.workspaceNamingEnabled)
    }

    /// Base URL dell'endpoint OpenAI-compatible. Vuoto -> torna al default. Il trailing slash viene
    /// normalizzato al momento della richiesta (nel controller), non qui.
    func setWorkspaceNamingBaseURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? Self.defaultNamingBaseURL : trimmed
        guard value != workspaceNamingBaseURL else { return }
        workspaceNamingBaseURL = value
        defaults.set(value, forKey: Keys.workspaceNamingBaseURL)
    }

    func setWorkspaceNamingModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? Self.defaultNamingModel : trimmed
        guard value != workspaceNamingModel else { return }
        workspaceNamingModel = value
        defaults.set(value, forKey: Keys.workspaceNamingModel)
    }
}
