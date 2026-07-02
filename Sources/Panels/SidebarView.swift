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

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        onNewWorkspace: @escaping () -> Void,
        onTitleBarDoubleClick: @escaping () -> Void = {}
    ) {
        self.store = store
        self.settings = settings
        self.onNewWorkspace = onNewWorkspace
        self.onTitleBarDoubleClick = onTitleBarDoubleClick
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        return VStack(spacing: 0) {
            header(colors)
            Divider()
            list(colors)
        }
        .frame(minWidth: 180)
        .background(colors.background)
    }

    /// Header sulla stessa riga dei semafori della finestra (full-size content view): parte dopo
    /// il loro ingombro e ha la stessa altezza della strip del titolo per allineare le baseline.
    private func header(_ colors: ChromeColors) -> some View {
        HStack {
            Text("Relay")
                .font(Theme.Typography.title)
                .foregroundStyle(colors.foreground)
            Spacer()
            Button(action: onNewWorkspace) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(colors.secondary)
            .help("New workspace")
        }
        .padding(.leading, Theme.Metrics.trafficLightsInset)
        .padding(.trailing, Theme.Spacing.md)
        .frame(height: Theme.Metrics.titleBarHeight)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onTitleBarDoubleClick() }
    }

    private func list(_ colors: ChromeColors) -> some View {
        List(selection: selectionBinding) {
            Section {
                ForEach(store.workspaces) { workspace in
                    row(workspace, colors: colors).tag(workspace.id)
                }
                .onMove { store.moveWorkspaces(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Workspaces")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(colors.secondary)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(colors.background)
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedWorkspaceID },
            set: { if let id = $0 { store.selectWorkspace(id) } }
        )
    }

    private func row(_ workspace: Workspace, colors: ChromeColors) -> some View {
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
        .padding(.vertical, Theme.Spacing.xxs)
        .contextMenu {
            Button(workspace.pinned ? "Unpin" : "Pin") { store.togglePin(workspace.id) }
            Button("Close", role: .destructive) { store.closeWorkspace(workspace.id) }
        }
    }
}
