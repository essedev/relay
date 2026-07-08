import Core
import SwiftUI
import WorkspaceModel

/// Binding di `SettingsView`, estratti per tenere il corpo del tipo compatto. Ognuno legge una
/// preferenza e la scrive col setter di `AppSettings` (unica via di scrittura).
extension SettingsView {
    var fontRange: ClosedRange<Double> {
        AppSettings.minFontSize ... AppSettings.maxFontSize
    }

    var fontBinding: Binding<Double> {
        Binding(get: { settings.fontSize }, set: { settings.setFontSize($0) })
    }

    /// Tag sentinella per il monospace di sistema (`fontName == nil`): SwiftUI Picker non gestisce
    /// bene i tag opzionali, quindi mappiamo nil a questa stringa al confine del binding.
    static var systemFontTag: String {
        "__system__"
    }

    var fontFamilyBinding: Binding<String> {
        Binding(
            get: { settings.fontName ?? Self.systemFontTag },
            set: { settings.setFontName($0 == Self.systemFontTag ? nil : $0) }
        )
    }

    var cursorBlinkBinding: Binding<Bool> {
        Binding(get: { settings.cursorBlink }, set: { settings.setCursorBlink($0) })
    }

    var autoResumeBinding: Binding<Bool> {
        Binding(get: { settings.autoResumeAgents }, set: { settings.setAutoResumeAgents($0) })
    }

    var pendingDecayBinding: Binding<Int> {
        Binding(get: { settings.pendingDecayHours }, set: { settings.setPendingDecayHours($0) })
    }

    var checkForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { settings.checkForUpdatesAutomatically },
            set: { settings.setCheckForUpdatesAutomatically($0) }
        )
    }

    var notificationsEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.notificationsEnabled },
            set: { settings.setNotificationsEnabled($0) }
        )
    }

    var notifyNeedsInputBinding: Binding<Bool> {
        Binding(get: { settings.notifyOnNeedsInput }, set: { settings.setNotifyOnNeedsInput($0) })
    }

    var notifyCompletedBinding: Binding<Bool> {
        Binding(get: { settings.notifyOnCompleted }, set: { settings.setNotifyOnCompleted($0) })
    }

    var notificationSoundBinding: Binding<Bool> {
        Binding(get: { settings.notificationSound }, set: { settings.setNotificationSound($0) })
    }

    var notificationSoundNameBinding: Binding<String> {
        Binding(
            get: { settings.notificationSoundName },
            set: {
                settings.setNotificationSoundName($0)
                NotificationSoundPreview.play($0) // anteprima udibile alla scelta
            }
        )
    }
}

/// Categoria di impostazioni (voce nella sidebar del pannello).
enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case terminal
    case agents
    case notifications
    case updates
    case shortcuts

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .terminal: "Terminal"
        case .agents: "Agents"
        case .notifications: "Notifications"
        case .updates: "Updates"
        case .shortcuts: "Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .appearance: "paintbrush"
        case .terminal: "terminal"
        case .agents: "sparkles"
        case .notifications: "bell"
        case .updates: "arrow.down.circle"
        case .shortcuts: "keyboard"
        }
    }
}

/// Voce categoria nella sidebar, con selezione/hover dal tema (come le righe workspace).
struct CategoryRow: View {
    let category: SettingsCategory
    let selected: Bool
    let colors: ChromeColors
    let onSelect: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: category.icon)
                .font(Theme.Typography.rowIcon)
                .frame(width: 18)
                .foregroundStyle(selected ? colors.accent : colors.secondary)
            Text(category.title)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(selected ? colors.selection : hovered ? colors.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
    }
}

/// Riga di scelta tema: nome + anteprima della palette del tema stesso (sfondo + qualche ANSI),
/// con selezione/hover dal tema corrente. Cliccare seleziona.
struct ThemeRow: View {
    let theme: RelayTheme
    let selected: Bool
    let chrome: ChromeColors
    let onSelect: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(Theme.Typography.rowIcon)
                .foregroundStyle(selected ? chrome.accent : chrome.secondary.opacity(0.4))
            Text(theme.name)
                .font(Theme.Typography.item)
                .foregroundStyle(chrome.foreground)
            Spacer()
            swatches
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(selected ? chrome.selection : hovered ? chrome.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
    }

    /// Campioni ANSI (rosso, verde, blu, magenta) su sfondo del tema: mostra com'è davvero.
    private var swatches: some View {
        HStack(spacing: 3) {
            ForEach([1, 2, 4, 5], id: \.self) { index in
                Circle()
                    .fill(Color(theme.ansiColor(index)))
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(theme.background)))
        .overlay(
            RoundedRectangle(cornerRadius: 4).strokeBorder(Color(theme.selection), lineWidth: 1)
        )
    }
}

/// Un blocco di impostazioni: categoria + parole chiave per la ricerca + la sua vista.
struct SettingsBlock: Identifiable {
    let id: String
    let category: SettingsCategory
    let keywords: [String]
    let view: AnyView
}
