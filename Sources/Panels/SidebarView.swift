import SwiftUI
import WorkspaceModel

/// Sidebar: elenco dei workspace con selezione, pin, riordino. Pannello SwiftUI isolato,
/// disaccoppiato dal view tree del terminale. La creazione di un workspace è delegata all'app
/// (`onNewWorkspace`), che sceglie la cartella progetto. Colori derivati dal tema corrente.
public struct SidebarView: View {
    let store: WorkspaceStore
    let settings: AppSettings
    let onNewWorkspace: () -> Void
    /// Doppio click sull'header (riga dei semafori) = comportamento title bar di macOS (zoom).
    let onTitleBarDoubleClick: () -> Void
    /// Chiude la sidebar (bottone in alto a destra; riappare nella strip del titolo).
    let onToggleSidebar: () -> Void

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        onNewWorkspace: @escaping () -> Void,
        onTitleBarDoubleClick: @escaping () -> Void = {},
        onToggleSidebar: @escaping () -> Void = {}
    ) {
        self.store = store
        self.settings = settings
        self.onNewWorkspace = onNewWorkspace
        self.onTitleBarDoubleClick = onTitleBarDoubleClick
        self.onToggleSidebar = onToggleSidebar
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        return VStack(spacing: 0) {
            trafficLightsStrip
            workspacesHeader(colors)
            list(colors)
        }
        .frame(minWidth: 200)
        .background(colors.background)
    }

    /// Riga dei semafori (full-size content view): zona di drag e doppio click (zoom finestra),
    /// col toggle della sidebar in alto a destra.
    private var trafficLightsStrip: some View {
        let colors = ChromeColors(settings.theme)
        return HStack {
            Spacer()
            Button(action: onToggleSidebar) {
                Image(systemName: "sidebar.leading")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(colors.secondary)
            .help("Hide sidebar (⌘B)")
        }
        .padding(.trailing, Theme.Spacing.md)
        .frame(height: Theme.Metrics.titleBarHeight)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onTitleBarDoubleClick() }
    }

    private func workspacesHeader(_ colors: ChromeColors) -> some View {
        HStack {
            Text("Workspaces")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.secondary)
            Spacer()
            Button(action: onNewWorkspace) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(colors.secondary)
            .help("New workspace")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
    }

    /// Selezione disegnata da noi coi colori del tema (niente highlight di sistema): List senza
    /// binding di selezione, righe custom con tap + hover, `onMove` per il riordino.
    private func list(_ colors: ChromeColors) -> some View {
        List {
            ForEach(store.workspaces) { workspace in
                WorkspaceRow(
                    workspace: workspace,
                    selected: workspace.id == store.selectedWorkspaceID,
                    colors: colors,
                    onSelect: { store.selectWorkspace(workspace.id) },
                    onTogglePin: { store.togglePin(workspace.id) },
                    onClose: { store.closeWorkspace(workspace.id) }
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: 1,
                    leading: Theme.Spacing.sm,
                    bottom: 1,
                    trailing: Theme.Spacing.sm
                ))
            }
            .onMove { store.moveWorkspaces(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(colors.background)
    }
}

/// Riga workspace con selezione/hover dal tema. View separata per lo stato di hover locale.
private struct WorkspaceRow: View {
    let workspace: Workspace
    let selected: Bool
    let colors: ChromeColors
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onClose: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: workspace.pinned ? "pin.fill" : "folder")
                .foregroundStyle(workspace.pinned ? colors.accent : colors.secondary)
                .font(.system(size: 12))
            Text(workspace.name)
                .font(Theme.Typography.item)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.xs)
            AgentBadge(kind: .forWorkspace(workspace), colors: colors)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(selected ? colors.selection : hovered ? colors.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
        .contextMenu {
            Button(workspace.pinned ? "Unpin" : "Pin", action: onTogglePin)
            Button("Close", role: .destructive, action: onClose)
        }
    }
}
