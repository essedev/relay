import SwiftUI

/// Metadati e callback per gestire gli hook di un agente senza far dipendere `Panels` dagli
/// installer concreti. Il composition root ne crea uno per Claude Code e uno per Codex.
/// Come stanno gli hook di un agente, per il blocco in Settings. Panels non importa
/// `HookInstaller` (dipende solo da Core/AgentProtocol/WorkspaceModel): il composition root mappa
/// `RelayHookState` qui sopra. `outOfDate` esiste perché un drift letto come "non installato" e'
/// falso e porta fuori strada: gli hook ci sono e funzionano, ne manca qualcuno.
public enum HookStatus: Equatable, Sendable {
    case absent
    case outOfDate(missing: [String])
    case installed

    /// Riga di stato. Il drift nomina gli eventi: "non installato" su una configurazione che
    /// funziona per sei hook su otto manda a cercare nel posto sbagliato.
    public var label: String {
        switch self {
        case .installed: "Installed"
        case .absent: "Not installed"
        case let .outOfDate(missing): "Out of date: missing \(missing.joined(separator: ", "))"
        }
    }

    /// Su un drift il bottone aggiorna, non reinstalla da zero: il setup è idempotente e rimette
    /// solo ciò che manca, preservando gli hook dell'utente.
    public var actionLabel: String {
        switch self {
        case .installed: "Uninstall"
        case .outOfDate: "Update"
        case .absent: "Install"
        }
    }
}

public struct HookControls: Identifiable {
    public let id: String
    public let title: String
    public let detail: String
    public let note: String?
    public let status: () -> HookStatus
    public let install: () throws -> Void
    public let uninstall: () throws -> Void

    public init(
        id: String,
        title: String,
        detail: String,
        note: String? = nil,
        status: @escaping () -> HookStatus,
        install: @escaping () throws -> Void,
        uninstall: @escaping () throws -> Void
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.note = note
        self.status = status
        self.install = install
        self.uninstall = uninstall
    }
}

/// Blocco impostazioni riusabile per installare/rimuovere gli hook di un agente.
struct AgentHooksBlock: View {
    let hooks: HookControls
    let colors: ChromeColors

    @State private var status: HookStatus = .absent
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
                StatusDot(color: dotColor, size: Theme.Metrics.statusDotCompact)
                Text(status.label)
                    .font(Theme.Typography.item)
                    .foregroundStyle(colors.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(status.actionLabel, action: toggle)
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.accent)
            }
            if let error {
                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(colors.error)
            }
        }
        .onAppear { status = hooks.status() }
    }

    private var dotColor: Color {
        switch status {
        case .installed: colors.accent
        case .outOfDate: colors.needsInput // ambra: funziona, ma chiede una mano
        case .absent: colors.secondary.opacity(0.5)
        }
    }

    private func toggle() {
        error = nil
        do {
            if status == .installed { try hooks.uninstall() } else { try hooks.install() }
            status = hooks.status()
        } catch {
            self.error = "Could not update hook configuration: \(error.localizedDescription)"
        }
    }
}
