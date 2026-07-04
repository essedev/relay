import SwiftUI

/// Callback per gestire gli hook di Claude Code dal pannello impostazioni, senza che `Panels`
/// dipenda da `HookInstaller`: il composition root li costruisce con `ClaudeHookInstaller` e il
/// path del `relay-cli` impacchettato. `nil` (passato a `SettingsView`) nasconde il blocco quando
/// il cli non è raggiungibile.
public struct HookControls {
    public let isInstalled: () -> Bool
    public let install: () throws -> Void
    public let uninstall: () throws -> Void

    public init(
        isInstalled: @escaping () -> Bool,
        install: @escaping () throws -> Void,
        uninstall: @escaping () throws -> Void
    ) {
        self.isInstalled = isInstalled
        self.install = install
        self.uninstall = uninstall
    }
}

/// Blocco impostazioni (categoria Agents) per installare/rimuovere gli hook di Claude Code in
/// `~/.claude/settings.json` col `relay-cli` impacchettato: così l'utente non deve trovarlo nel
/// PATH. Lo stato si rilegge a ogni apparizione e dopo ogni azione. Componente a sé (come
/// `ShortcutsList`) per tenere `SettingsView` entro il budget di dimensione.
struct ClaudeHooksBlock: View {
    let hooks: HookControls
    let colors: ChromeColors

    @State private var installed = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Claude Code hooks")
                .font(Theme.Typography.title)
                .foregroundStyle(colors.foreground)
            Text("Relay reads agent state from Claude Code hooks. Installing adds them to "
                + "~/.claude/settings.json (it keeps any hooks already there).")
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Circle()
                    .fill(installed ? colors.running : colors.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(installed ? "Installed" : "Not installed")
                    .font(Theme.Typography.item)
                    .foregroundStyle(colors.foreground)
                Spacer()
                Button(installed ? "Uninstall" : "Install", action: toggle)
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.accent)
            }
            if let error {
                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(colors.error)
            }
        }
        .onAppear { installed = hooks.isInstalled() }
    }

    private func toggle() {
        error = nil
        do {
            if installed { try hooks.uninstall() } else { try hooks.install() }
            installed = hooks.isInstalled()
        } catch {
            self.error = "Could not update settings.json: \(error.localizedDescription)"
        }
    }
}
