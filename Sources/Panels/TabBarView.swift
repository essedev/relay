import SwiftUI
import WorkspaceModel

/// Tab bar del workspace selezionato: i terminali del progetto, gestiti a tab. Pannello SwiftUI
/// isolato, montato sopra l'area del terminale (che è AppKit).
public struct TabBarView: View {
    let store: WorkspaceStore

    public init(store: WorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if let workspace = store.selectedWorkspace {
                content(for: workspace)
            } else {
                Color.clear
            }
        }
        .frame(height: Theme.Metrics.tabBarHeight)
        .background(Theme.Colors.tabBarBackground)
    }

    private func content(for workspace: Workspace) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(workspace.tabs) { tab in
                    tabItem(tab, in: workspace)
                }
                Button { store.addTab(to: workspace) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("New tab")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.sm)
        }
    }

    private func tabItem(_ tab: WorkspaceModel.Tab, in workspace: Workspace) -> some View {
        let selected = tab.id == workspace.selectedTabID
        return HStack(spacing: Theme.Spacing.xs) {
            AgentBadge(kind: .forTab(tab))
            Text(tab.title)
                .font(Theme.Typography.tab)
                .lineLimit(1)
            Button { store.closeTab(tab.id, in: workspace) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.borderless)
            .opacity(workspace.tabs.count > 1 ? 1 : 0)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(selected ? Theme.Colors.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .contentShape(Rectangle())
        .onTapGesture { store.selectTab(tab.id, in: workspace) }
    }
}
