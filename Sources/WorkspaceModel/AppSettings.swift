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
    public private(set) var sidebarCollapsed: Bool

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        themeName = defaults.string(forKey: Keys.themeName) ?? RelayTheme.relayDark.name
        let savedSize = defaults.double(forKey: Keys.fontSize)
        fontSize = savedSize == 0 ? RelayTheme.relayDark.fontSize : savedSize
        sidebarCollapsed = defaults.bool(forKey: Keys.sidebarCollapsed)
    }

    /// Temi selezionabili (per il picker delle impostazioni).
    public var availableThemes: [RelayTheme] {
        RelayTheme.all
    }

    /// Tema effettivo: quello scelto, con la dimensione font corrente applicata.
    public var theme: RelayTheme {
        let base = RelayTheme.all.first { $0.name == themeName } ?? .relayDark
        return base.withFontSize(fontSize)
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

    public func toggleSidebar() {
        sidebarCollapsed.toggle()
        defaults.set(sidebarCollapsed, forKey: Keys.sidebarCollapsed)
    }

    private func persist() {
        defaults.set(themeName, forKey: Keys.themeName)
        defaults.set(fontSize, forKey: Keys.fontSize)
    }

    private enum Keys {
        static let themeName = "relay.theme.name"
        static let fontSize = "relay.theme.fontSize"
        static let sidebarCollapsed = "relay.sidebar.collapsed"
    }
}
