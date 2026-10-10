import Core
import Observation
import SwiftUI

/// Stato osservabile del check aggiornamenti, condiviso tra il composition root (che lo popola dopo
/// la fetch di rete) e la sidebar (che mostra la pill). Data holder puro: nessuna rete qui, la fa
/// `UpdateController` in RelayApp.
@MainActor
@Observable
public final class UpdateAvailability {
    /// L'ultima release quando è più recente di quella installata e non è stata skippata; `nil`
    /// altrimenti (nessuna pill).
    public var latest: LatestRelease?
    /// Dove sta l'aggiornamento lanciato dalla pill.
    public var phase: UpgradePhase = .idle

    public init(latest: LatestRelease? = nil) {
        self.latest = latest
    }
}

/// Fasi dell'aggiornamento via Homebrew lanciato dalla pill. Niente annullamento: un `brew`
/// interrotto a metà lascia il cask in uno stato peggiore di uno che finisce.
public enum UpgradePhase: Equatable, Sendable {
    case idle
    case running
    /// La nuova versione è sul disco: manca solo il riavvio.
    case installed
    case failed(String)
}

/// Tutto ciò che serve alla sidebar per mostrare la pill di aggiornamento, in un unico valore così
/// l'init di `SidebarView` non si gonfia. `nil` = niente pill (es. `swift run` senza bundle, o
/// test).
/// Le azioni (clipboard, brew, riavvio, apri URL, skip) le fornisce il composition root: la view
/// non tocca AppKit.
public struct SidebarUpdateConfig {
    let availability: UpdateAvailability
    let currentVersion: String
    let upgradeCommand: String
    let onCopyCommand: () -> Void
    let onUpgrade: () -> Void
    let onRestart: () -> Void
    let onOpenRelease: () -> Void
    let onSkip: () -> Void

    public init(
        availability: UpdateAvailability,
        currentVersion: String,
        upgradeCommand: String,
        onCopyCommand: @escaping () -> Void,
        onUpgrade: @escaping () -> Void,
        onRestart: @escaping () -> Void,
        onOpenRelease: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.availability = availability
        self.currentVersion = currentVersion
        self.upgradeCommand = upgradeCommand
        self.onCopyCommand = onCopyCommand
        self.onUpgrade = onUpgrade
        self.onRestart = onRestart
        self.onOpenRelease = onOpenRelease
        self.onSkip = onSkip
    }
}

/// Pill transitoria in fondo alla sidebar: compare solo quando c'è una release più recente. Click
/// -> popover che aggiorna con Homebrew senza uscire dall'app, poi propone il riavvio. Il comando
/// resta copiabile per chi preferisce lanciarlo da sé o quando brew fallisce.
struct UpdateBanner: View {
    let config: SidebarUpdateConfig
    let colors: ChromeColors
    @State private var showDetails = false
    @State private var copied = false

    private var phase: UpgradePhase {
        config.availability.phase
    }

    var body: some View {
        if let latest = config.availability.latest {
            Button { showDetails.toggle() } label: {
                pill(latest)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .popover(isPresented: $showDetails, arrowEdge: .trailing) {
                details(latest)
            }
        }
    }

    private func pill(_ latest: LatestRelease) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            if phase == .running {
                ProgressView().controlSize(.mini)
            } else {
                StatusDot(color: colors.accent, size: Theme.Metrics.presenceDot)
            }
            Text(pillTitle(latest))
                .font(Theme.Typography.subtitle)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(colors.secondary)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(colors.accent.opacity(0.12))
        )
        .contentShape(Rectangle())
    }

    private func pillTitle(_ latest: LatestRelease) -> String {
        switch phase {
        case .idle, .failed: "Update available \(latest.version.description)"
        case .running: "Updating to \(latest.version.description)\u{2026}"
        case .installed: "Restart to finish updating"
        }
    }

    private func details(_ latest: LatestRelease) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(phase == .installed ? "Update installed" : "Update available")
                .font(Theme.Typography.title)
            Text("Relay \(config.currentVersion) \u{2192} \(latest.version.description)")
                .font(Theme.Typography.subtitle)
                .foregroundStyle(colors.secondary)

            action

            if case let .failed(message) = phase {
                Text(message)
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(colors.error)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if phase != .installed {
                manualCommand
            }

            Divider()

            HStack {
                if phase != .running, phase != .installed {
                    Button("Skip this version", action: config.onSkip)
                        .buttonStyle(.plain)
                        .foregroundStyle(colors.secondary)
                }
                Spacer()
                Button("Release notes", action: config.onOpenRelease)
            }
            .font(Theme.Typography.subtitle)
        }
        .padding(Theme.Spacing.md)
        .frame(width: 320)
    }

    /// L'azione principale per la fase: aggiorna, attendi, riavvia o riprova.
    @ViewBuilder private var action: some View {
        switch phase {
        case .idle:
            Button("Update", action: config.onUpgrade)
                .buttonStyle(.borderedProminent)
        case .running:
            HStack(spacing: Theme.Spacing.xs) {
                ProgressView().controlSize(.small)
                Text("Homebrew is updating Relay\u{2026} You can keep working.")
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(colors.secondary)
            }
        case .installed:
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Restart to use the new version. Agent sessions can be resumed after it.")
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(colors.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Restart Relay") {
                    showDetails = false
                    config.onRestart()
                }
                .buttonStyle(.borderedProminent)
            }
        case .failed:
            Button("Try again", action: config.onUpgrade)
                .buttonStyle(.borderedProminent)
        }
    }

    /// Il comando brew da copiare, per chi preferisce lanciarlo da sé.
    private var manualCommand: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Or run it yourself:")
                .font(Theme.Typography.subtitle)
                .foregroundStyle(colors.secondary)
            HStack(spacing: Theme.Spacing.xs) {
                CommandChip(
                    config.upgradeCommand,
                    colors: colors,
                    weight: .regular,
                    // Il popup dell'update usa il material di sistema, non i colori del tema: il
                    // testo del comando resta sulla label di sistema (`.primary`), adattiva a
                    // light/dark, come prima (senza, un tema chiaro su OS scuro perde contrasto).
                    foreground: .primary,
                    // Il box si estende a tutta la larghezza disponibile: il comando va a capo su
                    // due righe e ritornerebbe una larghezza minore di quella proposta, staccando
                    // l'icona dal bordo destro. Espanso, l'azione si ancora a destra e la riga si
                    // allinea al resto del popover.
                    maxWidth: .infinity,
                    alignment: .leading,
                    fill: 1.0,
                    selectable: true
                )
                Button {
                    config.onCopyCommand()
                    copied = true
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? colors.completed : colors.secondary)
                .help(copied ? "Copied" : "Copy command")
            }
        }
    }
}
