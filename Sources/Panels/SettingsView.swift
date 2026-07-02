import SwiftUI
import WorkspaceModel

/// Pannello impostazioni (Cmd+,). Struttura a categorie (segmented themed, non `TabView` di
/// sistema) con campo di ricerca che filtra per parole chiave. Ogni impostazione è un "blocco"
/// dichiarativo (categoria + keywords + vista): unica fonte sia per le categorie sia per la
/// ricerca,
/// così aggiungere una voce è una riga sola. Le scelte passano per i setter di `AppSettings`.
public struct SettingsView: View {
    let settings: AppSettings
    @State private var search = ""
    @State private var category: SettingsCategory = .appearance

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        VStack(spacing: 0) {
            searchBar(colors)
            Divider()
            content(colors)
        }
        .frame(width: 440, height: 330)
        .background(colors.background)
    }

    // MARK: - Struttura

    @ViewBuilder
    private func content(_ colors: ChromeColors) -> some View {
        let blocks = allBlocks(colors)
        if search.isEmpty {
            byCategory(blocks, colors)
        } else {
            searchResults(blocks, colors)
        }
    }

    private func byCategory(_ blocks: [SettingsBlock], _ colors: ChromeColors) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $category) {
                ForEach(SettingsCategory.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Theme.Spacing.md)

            Divider()
            page(blocks.filter { $0.category == category }, colors: colors, empty: nil)
        }
    }

    private func searchResults(_ blocks: [SettingsBlock], _ colors: ChromeColors) -> some View {
        let query = search.lowercased()
        let matches = blocks.filter { block in block.keywords.contains { $0.contains(query) } }
        return page(matches, colors: colors, empty: "No settings match \u{201C}\(search)\u{201D}")
    }

    private func page(
        _ blocks: [SettingsBlock],
        colors: ChromeColors,
        empty: String?
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if blocks.isEmpty, let empty {
                    Text(empty)
                        .font(Theme.Typography.item)
                        .foregroundStyle(colors.secondary)
                } else {
                    ForEach(blocks) { $0.view }
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func searchBar(_ colors: ChromeColors) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(colors.secondary)
            TextField("Search settings", text: $search)
                .textFieldStyle(.plain)
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
        .frame(height: 38)
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
                keywords: ["font", "size", "text", "zoom"],
                view: AnyView(fontBlock(colors))
            ),
            SettingsBlock(
                id: "cursor",
                category: .terminal,
                keywords: ["cursor", "caret", "blink", "terminal"],
                view: AnyView(cursorBlock(colors))
            ),
        ]
    }

    private func themeBlock(_ colors: ChromeColors) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Theme")
                .font(Theme.Typography.title)
                .foregroundStyle(colors.foreground)
            Picker("Theme", selection: themeBinding) {
                ForEach(settings.availableThemes, id: \.name) { theme in
                    Text(theme.name).tag(theme.name)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("PREVIEW")
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .padding(.top, Theme.Spacing.xs)
            palettePreview
        }
    }

    /// Anteprima (sola lettura) della palette del tema selezionato: gli ANSI 1-6 e un campione di
    /// testo su sfondo del tema. Non è un controllo, mostra soltanto com'è il tema.
    private var palettePreview: some View {
        let theme = settings.theme
        return HStack(spacing: Theme.Spacing.xs) {
            ForEach(1 ..< 7, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(theme.ansiColor(index)))
                    .frame(width: 18, height: 18)
            }
            Spacer()
            Text("Aa")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(theme.foreground))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(theme.background))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color(theme.selection), lineWidth: 1)
                        )
                )
        }
    }

    private func fontBlock(_ colors: ChromeColors) -> some View {
        row("Font size", colors) {
            Stepper(value: fontBinding, in: fontRange, step: 1) {
                Text("\(Int(settings.fontSize)) pt")
                    .font(Theme.Typography.item.monospacedDigit())
                    .foregroundStyle(colors.foreground)
            }
            .fixedSize()
        }
    }

    private func cursorBlock(_ colors: ChromeColors) -> some View {
        row("Blink cursor", colors) {
            Toggle("", isOn: cursorBlinkBinding)
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

    private var themeBinding: Binding<String> {
        Binding(get: { settings.themeName }, set: { settings.selectTheme($0) })
    }

    private var fontBinding: Binding<Double> {
        Binding(get: { settings.fontSize }, set: { settings.setFontSize($0) })
    }

    private var cursorBlinkBinding: Binding<Bool> {
        Binding(get: { settings.cursorBlink }, set: { settings.setCursorBlink($0) })
    }
}

/// Categoria di impostazioni (segmented in cima al pannello).
private enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance
    case terminal

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .appearance: "Appearance"
        case .terminal: "Terminal"
        }
    }
}

/// Un blocco di impostazioni: categoria + parole chiave per la ricerca + la sua vista.
private struct SettingsBlock: Identifiable {
    let id: String
    let category: SettingsCategory
    let keywords: [String]
    let view: AnyView
}
