import SwiftUI
import WorkspaceModel

/// Pannello "About Relay" (menu Relay > About Relay). Look pulito ispirato ad "About This Mac":
/// icona, nome, tagline, versione, in colonna centrata. I colori vengono dal tema corrente
/// (`ChromeColors`) per restare coerenti con la chrome, non hardcoded (principio UI #6).
/// L'icona è `RelayMarkView` (procedurale): identica all'`.icns` del bundle e disponibile anche
/// nei build di sviluppo, dove `NSApp.applicationIconImage` darebbe l'icona generica.
public struct AboutView: View {
    let settings: AppSettings
    let version: String

    public init(settings: AppSettings, version: String) {
        self.settings = settings
        self.version = version
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        VStack(spacing: Theme.Spacing.sm) {
            RelayMarkView(size: 96)
            Text("Relay")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(colors.foreground)
            Text("Agent-aware native macOS terminal")
                .font(Theme.Typography.subtitle)
                .foregroundStyle(colors.secondary)
                .multilineTextAlignment(.center)
            Text("Version \(version)")
                .font(Theme.Typography.item)
                .foregroundStyle(colors.secondary)
                .textSelection(.enabled)
                .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
    }
}
