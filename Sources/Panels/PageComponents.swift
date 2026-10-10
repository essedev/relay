import SwiftUI
import WorkspaceModel

// Pezzi condivisi dalle pagine (Home, Projects): il chip di un progetto e lo stile dei bottoni.

/// Un progetto in forma di chip: colore del gruppo, nome, da quanto è fermo. Click = apri.
struct ProjectChip: View {
    let workspace: Workspace
    /// Il colore del suo gruppo (grigio se non ne ha uno).
    let tint: Color
    let now: Date
    let colors: ChromeColors
    let onOpen: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(workspace.name)
                .font(Theme.Typography.tab)
                .foregroundStyle(colors.foreground)
            if let age = SessionTriage.age(of: workspace.lastActiveAt, now: now) {
                Text(age)
                    .font(Theme.Typography.tab)
                    .foregroundStyle(colors.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md - 1)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(hovered ? colors.hover : colors.surface.opacity(0.7))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovered = $0 }
        .help("Open \(workspace.name)")
    }
}

/// Bottone delle pagine: piccolo, pieno tenue, nel registro della chrome.
struct PageButtonStyle: ButtonStyle {
    let colors: ChromeColors
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.tab)
            .foregroundStyle(prominent ? colors.background : colors.foreground)
            .padding(.horizontal, Theme.Spacing.md - 1)
            .padding(.vertical, Theme.Spacing.xs + 1)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(prominent ? colors.accent : colors.selection.opacity(
                        configuration.isPressed ? 1 : 0.7
                    ))
            )
            .contentShape(Rectangle())
    }
}
