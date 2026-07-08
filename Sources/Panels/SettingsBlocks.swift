import SwiftUI
import WorkspaceModel

/// Blocchi del pannello impostazioni, estratti da `SettingsView` per tenerne il corpo compatto
/// (come `SettingsComponents` per i binding). Ogni blocco è la vista di una singola impostazione;
/// `allBlocks` è l'unica fonte per categorie e ricerca. I metodi restano `private` a questo file:
/// solo `allBlocks` è internal, chiamato da `SettingsView.detail`.
extension SettingsView {
    func allBlocks(_ colors: ChromeColors) -> [SettingsBlock] {
        var blocks = fixedBlocks(colors)
        blocks.append(SettingsBlock(
            id: "updates",
            category: .updates,
            keywords: ["update", "version", "upgrade", "brew", "homebrew", "release"],
            view: AnyView(updatesBlock(colors))
        ))
        // La nomina automatica sta in Agents (dopo "pending", prima degli hook): l'append in coda
        // tiene l'ordine dato dal filtro per categoria in `detail`.
        if let naming {
            blocks.append(SettingsBlock(
                id: "naming",
                category: .agents,
                keywords: [
                    "naming", "name", "workspace", "auto", "llm", "openai", "model", "api key",
                    "rename",
                ],
                view: AnyView(WorkspaceNamingBlock(
                    settings: settings,
                    naming: naming,
                    colors: colors
                ))
            ))
        }
        // Gli hook stanno nella categoria Agents (dopo il blocco "pending"): l'append in coda li
        // lascia lì, perché il filtro per categoria in `detail` tiene l'ordine dell'array.
        if let hooks {
            blocks.append(SettingsBlock(
                id: "hooks",
                category: .agents,
                keywords: ["claude", "hooks", "install", "setup", "agent", "settings.json"],
                view: AnyView(ClaudeHooksBlock(hooks: hooks, colors: colors))
            ))
        }
        return blocks
    }

    private func fixedBlocks(_ colors: ChromeColors) -> [SettingsBlock] {
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
                id: "pending",
                category: .agents,
                keywords: ["pending", "attention", "decay", "expire", "completed", "dismiss"],
                view: AnyView(pendingBlock(colors))
            ),
            SettingsBlock(
                id: "notifications",
                category: .notifications,
                keywords: ["notification", "notify", "alert", "sound", "needs input", "finished"],
                view: AnyView(notificationsBlock(colors))
            ),
            SettingsBlock(
                id: "shortcuts",
                category: .shortcuts,
                keywords: ["shortcut", "shortcuts", "hotkey", "keys", "keyboard", "keybinding"],
                view: AnyView(ShortcutsList(settings: settings, colors: colors))
            ),
        ]
    }

    /// On (default) = al lancio confronta con l'ultima release e mostra la pill se disponibile.
    /// L'aggiornamento passa comunque da brew (o dal dmg): Relay non si auto-scarica.
    private func updatesBlock(_ colors: ChromeColors) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            toggleRow("Check for updates on launch", colors, checkForUpdatesBinding)
            Text(
                "Relay checks the latest release and shows a hint. Updating is done with Homebrew."
            )
            .font(Theme.Typography.subtitle)
            .foregroundStyle(colors.secondary)
        }
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

    /// Decadenza dei completamenti "in sospeso" (visti ma mai ripresi). "Never" (default) = si
    /// spengono solo con ripresa, dismiss o chiusura tab: niente perdita silenziosa.
    private func pendingBlock(_ colors: ChromeColors) -> some View {
        row("Auto-dismiss pending after", colors) {
            Picker("", selection: pendingDecayBinding) {
                ForEach(AppSettings.pendingDecayOptions, id: \.self) { hours in
                    Text(hours == 0 ? "Never" : "\(hours)h").tag(hours)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
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
