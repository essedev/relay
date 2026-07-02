import Core
import SwiftUI
import WorkspaceModel

/// Pannello impostazioni (Cmd+,). Layout master-detail: sidebar con ricerca + lista categorie a
/// sinistra, contenuto a destra. Ogni impostazione è un "blocco" dichiarativo (categoria + keywords
/// + vista): unica fonte per categorie e ricerca, così aggiungere una voce è una riga. Le scelte
/// passano per i setter di `AppSettings`.
public struct SettingsView: View {
    let settings: AppSettings
    @State private var search = ""
    @State private var category: SettingsCategory = .appearance

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        HStack(spacing: 0) {
            sidebar(colors)
            Divider()
            detail(colors)
        }
        .frame(width: 580, height: 400)
        .background(colors.background)
    }

    // MARK: - Sidebar

    private func sidebar(_ colors: ChromeColors) -> some View {
        VStack(spacing: 0) {
            searchBar(colors)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsCategory.allCases) { item in
                        CategoryRow(
                            category: item,
                            selected: category == item && search.isEmpty,
                            colors: colors,
                            onSelect: {
                                category = item
                                search = ""
                            }
                        )
                    }
                }
                .padding(Theme.Spacing.sm)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 184)
    }

    private func searchBar(_ colors: ChromeColors) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(colors.secondary)
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(colors.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 40)
    }

    // MARK: - Detail

    private func detail(_ colors: ChromeColors) -> some View {
        let blocks = allBlocks(colors)
        let shown: [SettingsBlock]
        let empty: String?
        if search.isEmpty {
            shown = blocks.filter { $0.category == category }
            empty = nil
        } else {
            let query = search.lowercased()
            shown = blocks.filter { block in block.keywords.contains { $0.contains(query) } }
            empty = "No settings match \u{201C}\(search)\u{201D}"
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if shown.isEmpty, let empty {
                    Text(empty)
                        .font(Theme.Typography.item)
                        .foregroundStyle(colors.secondary)
                } else {
                    ForEach(shown) { $0.view }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Blocchi (unica fonte: categorie + ricerca)

    private func allBlocks(_ colors: ChromeColors) -> [SettingsBlock] {
        [
            SettingsBlock(
                id: "theme",
                category: .appearance,
                keywords: ["theme", "dark", "light", "palette", "colors", "appearance", "preview"],
                view: AnyView(themeBlock(colors))
            ),
            SettingsBlock(
                id: "font",
                category: .appearance,
                keywords: ["font", "family", "typeface", "monospace", "size", "text", "zoom"],
                view: AnyView(fontBlock(colors))
            ),
            SettingsBlock(
                id: "cursor",
                category: .terminal,
                keywords: ["cursor", "caret", "blink", "terminal"],
                view: AnyView(cursorBlock(colors))
            ),
            SettingsBlock(
                id: "resume",
                category: .agents,
                keywords: ["agent", "claude", "resume", "session", "restore", "launch"],
                view: AnyView(resumeBlock(colors))
            ),
        ]
    }

    private func themeBlock(_ colors: ChromeColors) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Theme")
                .font(Theme.Typography.title)
                .foregroundStyle(colors.foreground)
            // Lista selezionabile (scala oltre i due temi, il segmented no), ogni riga anteprima la
            // sua palette.
            VStack(spacing: 3) {
                ForEach(settings.availableThemes, id: \.name) { theme in
                    ThemeRow(
                        theme: theme,
                        selected: theme.name == settings.themeName,
                        chrome: colors,
                        onSelect: { settings.selectTheme(theme.name) }
                    )
                }
            }
        }
    }

    private func fontBlock(_ colors: ChromeColors) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            row("Font family", colors) {
                Picker("", selection: fontFamilyBinding) {
                    Text("System").tag(Self.systemFontTag)
                    ForEach(MonospaceFonts.families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            row("Font size", colors) {
                Stepper(value: fontBinding, in: fontRange, step: 1) {
                    Text("\(Int(settings.fontSize)) pt")
                        .font(Theme.Typography.item.monospacedDigit())
                        .foregroundStyle(colors.foreground)
                }
                .fixedSize()
            }
        }
    }

    private func cursorBlock(_ colors: ChromeColors) -> some View {
        row("Blink cursor", colors) {
            Toggle("", isOn: cursorBlinkBinding)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    /// On = riprende la sessione da solo al re-focus; off (default) = mostra la barra "Resume".
    private func resumeBlock(_ colors: ChromeColors) -> some View {
        row("Auto-resume sessions", colors) {
            Toggle("", isOn: autoResumeBinding)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func row(
        _ title: String,
        _ colors: ChromeColors,
        @ViewBuilder control: () -> some View
    ) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
            Spacer()
            control()
        }
    }

    // MARK: - Binding

    private var fontRange: ClosedRange<Double> {
        AppSettings.minFontSize ... AppSettings.maxFontSize
    }

    private var fontBinding: Binding<Double> {
        Binding(get: { settings.fontSize }, set: { settings.setFontSize($0) })
    }

    /// Tag sentinella per il monospace di sistema (`fontName == nil`): SwiftUI Picker non gestisce
    /// bene i tag opzionali, quindi mappiamo nil a questa stringa al confine del binding.
    private static let systemFontTag = "__system__"

    private var fontFamilyBinding: Binding<String> {
        Binding(
            get: { settings.fontName ?? Self.systemFontTag },
            set: { settings.setFontName($0 == Self.systemFontTag ? nil : $0) }
        )
    }

    private var cursorBlinkBinding: Binding<Bool> {
        Binding(get: { settings.cursorBlink }, set: { settings.setCursorBlink($0) })
    }

    private var autoResumeBinding: Binding<Bool> {
        Binding(get: { settings.autoResumeAgents }, set: { settings.setAutoResumeAgents($0) })
    }
}

/// Categoria di impostazioni (voce nella sidebar del pannello).
private enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case terminal
    case agents

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .terminal: "Terminal"
        case .agents: "Agents"
        }
    }

    var icon: String {
        switch self {
        case .appearance: "paintbrush"
        case .terminal: "terminal"
        case .agents: "sparkles"
        }
    }
}

/// Voce categoria nella sidebar, con selezione/hover dal tema (come le righe workspace).
private struct CategoryRow: View {
    let category: SettingsCategory
    let selected: Bool
    let colors: ChromeColors
    let onSelect: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: category.icon)
                .font(.system(size: 12))
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
private struct ThemeRow: View {
    let theme: RelayTheme
    let selected: Bool
    let chrome: ChromeColors
    let onSelect: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
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
private struct SettingsBlock: Identifiable {
    let id: String
    let category: SettingsCategory
    let keywords: [String]
    let view: AnyView
}
