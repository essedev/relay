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
            SettingsBlock(
                id: "notifications",
                category: .notifications,
                keywords: ["notification", "notify", "alert", "sound", "needs input", "finished"],
                view: AnyView(notificationsBlock(colors))
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

    /// Notifiche macOS: master + per-tipo + suono. I sotto-controlli si disabilitano col master.
    private func notificationsBlock(_ colors: ChromeColors) -> some View {
        let on = settings.notificationsEnabled
        return VStack(spacing: Theme.Spacing.md) {
            toggleRow("Enable notifications", colors, notificationsEnabledBinding)
            Divider()
            toggleRow("When Claude needs input", colors, notifyNeedsInputBinding).disabled(!on)
            toggleRow("When Claude finishes", colors, notifyCompletedBinding).disabled(!on)
            Divider()
            toggleRow("Play sound", colors, notificationSoundBinding).disabled(!on)
            row("Sound", colors) {
                Picker("", selection: notificationSoundNameBinding) {
                    ForEach(AppSettings.availableSounds, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            .disabled(!on || !settings.notificationSound)
        }
    }

    private func toggleRow(
        _ title: String,
        _ colors: ChromeColors,
        _ binding: Binding<Bool>
    ) -> some View {
        row(title, colors) {
            Toggle("", isOn: binding)
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
}
