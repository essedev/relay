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

    public private(set) var themeName: String
    public private(set) var fontSize: Double
    /// Font family del terminale; `nil` = monospace di sistema (SF Mono). Sovrascrive il `fontName`
    /// del tema, come `fontSize`.
    public private(set) var fontName: String?
    public private(set) var cursorBlink: Bool
    public private(set) var sidebarCollapsed: Bool
    /// Al re-focus di una tab ripristinata con sessione agente: `true` inietta il resume da solo,
    /// `false` (default) mostra la barra "Resume". Default prudente: niente comandi automatici.
    public private(set) var autoResumeAgents: Bool

    /// Notifiche macOS (default tutte on). Master + per-tipo + suono + scelta del suono.
    public private(set) var notificationsEnabled: Bool
    public private(set) var notifyOnNeedsInput: Bool
    public private(set) var notifyOnCompleted: Bool
    public private(set) var notificationSound: Bool
    public private(set) var notificationSoundName: String

    /// Suoni di notifica selezionabili (nomi dei classici alert di sistema, `.aiff`). "Default" usa
    /// il suono di notifica di sistema.
    public static let availableSounds = [
        "Default", "Ping", "Glass", "Hero", "Submarine", "Funk", "Blow", "Pop",
    ]

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
        autoResumeAgents = defaults.bool(forKey: Keys.autoResumeAgents)
        notificationsEnabled = Self.boolDefaultingTrue(defaults, Keys.notificationsEnabled)
        notifyOnNeedsInput = Self.boolDefaultingTrue(defaults, Keys.notifyOnNeedsInput)
        notifyOnCompleted = Self.boolDefaultingTrue(defaults, Keys.notifyOnCompleted)
        notificationSound = Self.boolDefaultingTrue(defaults, Keys.notificationSound)
        notificationSoundName = defaults.string(forKey: Keys.notificationSoundName) ?? "Default"
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

    public func setAutoResumeAgents(_ enabled: Bool) {
        guard enabled != autoResumeAgents else { return }
        autoResumeAgents = enabled
        defaults.set(autoResumeAgents, forKey: Keys.autoResumeAgents)
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
        static let autoResumeAgents = "relay.agents.autoResume"
        static let notificationsEnabled = "relay.notifications.enabled"
        static let notifyOnNeedsInput = "relay.notifications.needsInput"
        static let notifyOnCompleted = "relay.notifications.completed"
        static let notificationSound = "relay.notifications.sound"
        static let notificationSoundName = "relay.notifications.soundName"
    }
}
