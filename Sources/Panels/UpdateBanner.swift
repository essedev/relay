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

    public init(latest: LatestRelease? = nil) {
        self.latest = latest
    }
}

/// Tutto ciò che serve alla sidebar per mostrare la pill di aggiornamento, in un unico valore così
/// l'init di `SidebarView` non si gonfia. `nil` = niente pill (es. `swift run` senza bundle, o
/// test).
/// Le azioni (clipboard, apri URL, skip) le fornisce il composition root: la view non tocca AppKit.
public struct SidebarUpdateConfig {
    let availability: UpdateAvailability
    let currentVersion: String
    let upgradeCommand: String
    let onCopyCommand: () -> Void
    let onRunUpdate: () -> Void
    let onOpenRelease: () -> Void
    let onSkip: () -> Void

    public init(
        availability: UpdateAvailability,
        currentVersion: String,
        upgradeCommand: String,
        onCopyCommand: @escaping () -> Void,
        onRunUpdate: @escaping () -> Void,
        onOpenRelease: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.availability = availability
        self.currentVersion = currentVersion
        self.upgradeCommand = upgradeCommand
        self.onCopyCommand = onCopyCommand
        self.onRunUpdate = onRunUpdate
        self.onOpenRelease = onOpenRelease
        self.onSkip = onSkip
    }
}

/// Pill transitoria in fondo alla sidebar (sopra la sezione Archive): compare solo quando c'è una
/// release più recente. Click -> popover col comando brew da copiare, la pagina della release e lo
/// skip. Nessun download in-app: l'aggiornamento passa da brew (vedi la gotcha "Check
/// aggiornamenti"
/// in CLAUDE.md).
struct UpdateBanner: View {
    let config: SidebarUpdateConfig
    let colors: ChromeColors
    @State private var showDetails = false
    @State private var copied = false

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
            Circle().fill(colors.accent).frame(width: 6, height: 6)
            Text("Update available \(latest.version.description)")
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

    private func details(_ latest: LatestRelease) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Update available")
                .font(Theme.Typography.title)
            Text("Relay \(config.currentVersion) → \(latest.version.description)")
                .font(Theme.Typography.subtitle)
                .foregroundStyle(colors.secondary)

            Text("Update with Homebrew:")
                .font(Theme.Typography.subtitle)
                .foregroundStyle(colors.secondary)
            commandRow

            Divider()

            HStack {
                Button("Skip this version", action: config.onSkip)
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.secondary)
                Spacer()
                Button("Release notes", action: config.onOpenRelease)
            }
            .font(Theme.Typography.subtitle)
        }
        .padding(Theme.Spacing.md)
        .frame(width: 320)
    }

    /// Comando brew + azioni: copia negli appunti oppure play (esegue in una tab dedicata).
    private var commandRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(config.upgradeCommand)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(colors.hover)
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
                Button {
                    showDetails = false
                    config.onRunUpdate()
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.accent)
                .help("Run in a new tab")
            }
            Text("Play runs it in a \u{201C}Relay Update\u{201D} tab. Quit and reopen Relay "
                + "when it finishes.")
                .font(.system(size: 10))
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
