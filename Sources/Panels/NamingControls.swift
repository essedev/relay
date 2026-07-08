import SwiftUI
import WorkspaceModel

/// Callback per la API key della nomina automatica, senza che `Panels` dipenda dal composition
/// root: la chiave vive in un file 0600 (`NamingCredentialStore`), qui passano solo le closure per
/// leggerne la presenza, salvarla e notificare un cambio di configurazione. `nil` (a
/// `SettingsView`)
/// nasconde il blocco. Base URL / model / toggle passano invece dai setter di `AppSettings`.
public struct NamingControls {
    public let hasKey: () -> Bool
    public let saveKey: (String?) -> Void
    /// Da chiamare dopo un cambio che tocca l'attivazione (toggle o chiave): il controller
    /// ri-valuta
    /// se far girare il poll (la presenza della chiave non è osservabile).
    public let onConfigChange: () -> Void

    public init(
        hasKey: @escaping () -> Bool,
        saveKey: @escaping (String?) -> Void,
        onConfigChange: @escaping () -> Void
    ) {
        self.hasKey = hasKey
        self.saveKey = saveKey
        self.onConfigChange = onConfigChange
    }
}

/// Blocco impostazioni (categoria Agents) per la nomina automatica dei workspace: toggle, endpoint
/// OpenAI-compatible (base URL + model) e API key (campo sicuro, salvata a parte). Componente a sé
/// (come `ClaudeHooksBlock`) per tenere `SettingsView` entro il budget di dimensione.
struct WorkspaceNamingBlock: View {
    let settings: AppSettings
    let naming: NamingControls
    let colors: ChromeColors

    @State private var keyDraft = ""
    @State private var keySaved = false

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.workspaceNamingEnabled },
            set: {
                settings.setWorkspaceNamingEnabled($0)
                naming.onConfigChange()
            }
        )
    }

    private var baseURLBinding: Binding<String> {
        Binding(
            get: { settings.workspaceNamingBaseURL },
            set: { settings.setWorkspaceNamingBaseURL($0) }
        )
    }

    private var modelBinding: Binding<String> {
        Binding(
            get: { settings.workspaceNamingModel },
            set: { settings.setWorkspaceNamingModel($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Workspace naming")
                .font(Theme.Typography.title)
                .foregroundStyle(colors.foreground)
            Text("Relay can auto-name a workspace from what you do in it (the directory you cd "
                + "into, a command you run, a Claude session) using an OpenAI-compatible model. "
                + "Manually renamed workspaces are never touched.")
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Enable auto-naming")
                    .font(Theme.Typography.item)
                    .foregroundStyle(colors.foreground)
                Spacer()
                Toggle("", isOn: enabledBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            fieldRow(
                "Base URL",
                text: baseURLBinding,
                placeholder: AppSettings.defaultNamingBaseURL
            )
            fieldRow("Model", text: modelBinding, placeholder: AppSettings.defaultNamingModel)
            apiKeyRow
        }
        .disabled(false)
        .onAppear { keySaved = naming.hasKey() }
    }

    /// Riga API key: campo sicuro + salva; se una chiave è già salvata mostra lo stato e "Remove"
    /// (non ri-mostriamo mai la chiave, solo la sua presenza).
    private var apiKeyRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("API key")
                    .font(Theme.Typography.item)
                    .foregroundStyle(colors.foreground)
                Spacer()
                SecureField("sk-…", text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Typography.item)
                    .frame(width: 200)
                Button("Save", action: saveKey)
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.accent)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack(spacing: Theme.Spacing.xs) {
                Circle()
                    .fill(keySaved ? colors.running : colors.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(keySaved ? "A key is saved" : "No key saved")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(colors.secondary)
                if keySaved {
                    Spacer()
                    Button("Remove", action: removeKey)
                        .buttonStyle(.plain)
                        .foregroundStyle(colors.error)
                }
            }
        }
    }

    private func fieldRow(
        _ title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
            Spacer()
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Typography.item)
                .frame(width: 200)
        }
    }

    private func saveKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        naming.saveKey(trimmed)
        naming.onConfigChange()
        keyDraft = ""
        keySaved = naming.hasKey()
    }

    private func removeKey() {
        naming.saveKey(nil)
        naming.onConfigChange()
        keySaved = naming.hasKey()
    }
}
