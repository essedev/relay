import SwiftUI
import WorkspaceModel

/// Sidebar: elenco dei workspace con selezione, pin, riordino. Pannello SwiftUI isolato,
/// disaccoppiato dal view tree del terminale. La creazione di un workspace è delegata all'app
/// (`onNewWorkspace`), che sceglie la cartella progetto.
public struct SidebarView: View {
    let store: WorkspaceStore
    let onNewWorkspace: () -> Void

    public init(store: WorkspaceStore, onNewWorkspace: @escaping () -> Void) {
        self.store = store
        self.onNewWorkspace = onNewWorkspace
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
        .frame(minWidth: 180)
    }

    private var header: some View {
        HStack {
            Text("Relay").font(Theme.Typography.title)
            Spacer()
            Button(action: onNewWorkspace) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New workspace")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var list: some View {
        List(selection: selectionBinding) {
            Section("Workspaces") {
                ForEach(store.workspaces) { workspace in
                    row(workspace).tag(workspace.id)
                }
                .onMove { store.moveWorkspaces(fromOffsets: $0, toOffset: $1) }
            }
        }
        .listStyle(.sidebar)
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { store.selectedWorkspaceID },
            set: { if let id = $0 { store.selectWorkspace(id) } }
        )
    }

    private func row(_ workspace: Workspace) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: workspace.pinned ? "pin.fill" : "folder")
                .foregroundStyle(workspace.pinned ? Theme.Colors.accent : Theme.Colors.secondary)
                .font(.system(size: 12))
            Text(workspace.name)
                .font(Theme.Typography.item)
                .lineLimit(1)
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .contextMenu {
            Button(workspace.pinned ? "Unpin" : "Pin") { store.togglePin(workspace.id) }
            Button("Close", role: .destructive) { store.closeWorkspace(workspace.id) }
        }
    }
}
