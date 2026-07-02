import SwiftUI
import WorkspaceModel

/// Toggle della sidebar, montato come overlay a posizione fissa accanto ai semafori, sopra il
/// contenuto. Un'unica icona per aprire e chiudere: niente scambi di bottoni durante l'animazione
/// del collasso.
public struct SidebarToggleButton: View {
    let settings: AppSettings
    let onToggle: () -> Void

    public init(settings: AppSettings, onToggle: @escaping () -> Void) {
        self.settings = settings
        self.onToggle = onToggle
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        Button(action: onToggle) {
            Image(systemName: "sidebar.leading")
                .font(.system(size: 13))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(colors.secondary)
        .help(settings.sidebarCollapsed ? "Show sidebar (⌘B)" : "Hide sidebar (⌘B)")
        .padding(.horizontal, Theme.Spacing.sm)
    }
}
