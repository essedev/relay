import SwiftUI
import WorkspaceModel

/// Pagina "attenzione" dell'onboarding: i quattro segnali sono righe cliccabili e la preview a
/// destra (riga di sidebar + mini terminale col ring) mostra dal vivo cosa fa Relay in quello
/// stato, coi componenti veri (`AgentBadge`, colori ANSI del tema).
struct AttentionPage: View {
    let colors: ChromeColors

    @State private var selected: AttentionDemoState = .needsInput

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            PageHeader(
                "Know what needs you",
                subtitle: "Every session gets a live badge in the sidebar and tab bar. "
                    + "Click a state to see what Relay shows you.",
                colors: colors
            )
            HStack(alignment: .top, spacing: Theme.Spacing.lg * 1.5) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(AttentionDemoState.allCases, id: \.self) { state in
                        stateRow(state)
                    }
                }
                .frame(width: 190)
                AttentionPreview(state: selected, colors: colors)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, Theme.Spacing.xs)
            Spacer(minLength: 0)
            Text("Interacting with the terminal turns the strong signal into the quiet one. "
                + "Only resuming the conversation clears it.")
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stateRow(_ state: AttentionDemoState) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { selected = state }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                AgentBadge(kind: state.badge, colors: colors)
                    .frame(width: 14, alignment: .center)
                Text(state.title)
                    .font(Theme.Typography.item.weight(state == selected ? .medium : .regular))
                    .foregroundStyle(state == selected ? colors.foreground : colors.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(state == selected ? colors.selection : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// I quattro segnali della demo, con tutto il materiale della preview.
enum AttentionDemoState: CaseIterable {
    case running, needsInput, doneUnseen, pending

    var title: String {
        switch self {
        case .running: "Running"
        case .needsInput: "Needs input"
        case .doneUnseen: "Done, unseen"
        case .pending: "Pending"
        }
    }

    var badge: BadgeKind {
        switch self {
        case .running: .running
        case .needsInput: .needsInput
        case .doneUnseen: .completed
        case .pending: .pending
        }
    }

    /// Ultima riga del mini terminale.
    var terminalLine: String {
        switch self {
        case .running: "Refactoring the auth module\u{2026}"
        case .needsInput: "Run npm test? (y/n)"
        case .doneUnseen, .pending: "Done. 12 files changed,\nall tests passing."
        }
    }

    /// Cosa fa Relay in questo stato (caption sotto la preview).
    var caption: String {
        switch self {
        case .running:
            "Claude is working. Leave the tab: Relay keeps watching and the badge spins."
        case .needsInput:
            "Claude asked you something: notification, pulsing ring, and the workspace "
                + "bumps to the top of the sidebar."
        case .doneUnseen:
            "Finished while you were away: green ring around the terminal, notification, "
                + "sidebar bump."
        case .pending:
            "Seen but not resumed: the ring is off, a quiet dot stays until you reply, "
                + "dismiss it, or it decays."
        }
    }
}

/// Preview live di uno stato: riga di sidebar finta (dove vive il badge) + mini terminale con il
/// ring di attenzione. Il ring pulsa per `needsInput`, come quello vero.
struct AttentionPreview: View {
    let state: AttentionDemoState
    let colors: ChromeColors

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            sidebarRow
            terminal
            Text(state.caption)
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 42, alignment: .topLeading) // altezza stabile tra gli stati
        }
    }

    private var sidebarRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "folder")
                .font(Theme.Typography.subtitle)
                .foregroundStyle(colors.secondary)
            Text("api-refactor")
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
            Spacer(minLength: 0)
            AgentBadge(kind: state.badge, colors: colors)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs + 1)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(colors.hover)
        )
    }

    private var terminal: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("\u{276F}")
                    .foregroundStyle(colors.accent)
                Text("claude")
                    .foregroundStyle(colors.foreground)
            }
            .font(.system(size: 11, design: .monospaced))
            Text(state.terminalLine)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(colors.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(colors.selection.opacity(0.3))
        )
        .overlay(
            // Ricreata al cambio stato (`id`): l'animazione del pulse riparte pulita.
            AttentionPreviewRing(state: state, colors: colors)
                .id(state)
        )
    }
}

/// Bordo del mini terminale: verde statico (done), giallo pulsante (needs input), spento altrove.
/// Stessa grammatica dell'`AttentionRingView` reale.
struct AttentionPreviewRing: View {
    let state: AttentionDemoState
    let colors: ChromeColors

    @State private var dim = false

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.sm)
            .stroke(ringColor, lineWidth: 2)
            .opacity(state == .needsInput ? (dim ? 0.35 : 1) : 1)
            .animation(
                state == .needsInput
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : nil,
                value: dim
            )
            .onAppear { dim = true }
    }

    private var ringColor: Color {
        switch state {
        case .running, .pending: .clear
        case .needsInput: colors.needsInput
        case .doneUnseen: colors.completed
        }
    }
}
