import SwiftUI

/// Metadati e callback per gestire gli hook di un agente senza far dipendere `Panels` dagli
/// installer concreti. Il composition root ne crea uno per Claude Code e uno per Codex.
public struct HookControls: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let note: String?
    public let isInstalled: () -> Bool
    public let install: () throws -> Void
    public let uninstall: () throws -> Void

    public init(
        id: String,
        title: String,
        detail: String,
        note: String? = nil,
        isInstalled: @escaping () -> Bool,
        install: @escaping () throws -> Void,
        uninstall: @escaping () throws -> Void
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.note = note
        self.isInstalled = isInstalled
        self.install = install
        self.uninstall = uninstall
    }
}

/// Blocco impostazioni riusabile per installare/rimuovere gli hook di un agente.
struct AgentHooksBlock: View {
    let hooks: HookControls
    let colors: ChromeColors

    @State private var installed = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(hooks.title)
                .font(Theme.Typography.title)
                .foregroundStyle(colors.foreground)
            Text(hooks.detail)
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note = hooks.note {
                Text(note)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                StatusDot(
                    color: installed ? colors.accent : colors.secondary.opacity(0.5),
                    size: Theme.Metrics.statusDotCompact
                )
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
            self.error = "Could not update hook configuration: \(error.localizedDescription)"
        }
    }
}
