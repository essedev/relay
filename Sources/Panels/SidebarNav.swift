import SwiftUI
import WorkspaceModel

/// La testa della sidebar: il campo che apre la palette (`⌘P`) e le due pagine, Home e Projects.
/// Sono posti dove andare, non progetti: stanno sopra la lista e si accendono quando la finestra
/// li mostra (`RelayWindow.page`).
struct SidebarNav: View {
    let store: WorkspaceStore
    let windowID: UUID
    let colors: ChromeColors
    let onShowPalette: () -> Void
    let onShowPage: (WindowPage) -> Void

    var body: some View {
        let page = WindowPageView.effectivePage(store, windowID: windowID)
        let needs = HomeModel.needsYou(store.workspaces).count
        VStack(spacing: 2) {
            searchField
                .padding(.bottom, Theme.Spacing.sm - 2)
            NavRow(
                symbol: "house",
                title: "Home",
                selected: page == .home,
                badge: needs > 0 ? "\(needs)" : nil,
                colors: colors
            ) { onShowPage(.home) }
            NavRow(
                symbol: "square.grid.2x2",
                title: "Projects",
                selected: page == .projects,
                badge: nil,
                colors: colors
            ) { onShowPage(.projects) }
        }
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.top, Theme.Spacing.xs)
    }

    /// Non è un campo vero: un click apre la palette, dove si scrive. Così la ricerca ha un solo
    /// posto, con la sua tastiera, e la sidebar non deve gestire un secondo elenco di risultati.
    private var searchField: some View {
        Button(action: onShowPalette) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.Typography.rowIcon)
                Text("Go to project\u{2026}")
                    .font(Theme.Typography.item)
                Spacer(minLength: 0)
                Text("\u{2318}P")
                    .font(Theme.Typography.subtitle)
            }
            .foregroundStyle(colors.secondary)
            .padding(.horizontal, Theme.Spacing.md - 2)
            .padding(.vertical, Theme.Spacing.xs + 3)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md).fill(colors.terminalWell)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(colors.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Go to project (\u{2318}P)")
    }
}

/// Una voce di navigazione: icona, titolo, e un numero ambra se qualcosa ti aspetta lì.
private struct NavRow: View {
    let symbol: String
    let title: String
    let selected: Bool
    let badge: String?
    let colors: ChromeColors
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md - 2) {
            Image(systemName: symbol)
                .font(Theme.Typography.rowIcon)
                .foregroundStyle(selected ? colors.accent : colors.secondary)
                .frame(width: 16)
            Text(title)
                .font(Theme.Typography.item)
                .foregroundStyle(selected || hovered ? colors.foreground : colors.secondary)
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(Theme.Typography.subtitle.weight(.semibold))
                    .foregroundStyle(colors.needsInput)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm + 1)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(selected ? colors.rowSelected : hovered ? colors.rowHover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
    }
}
