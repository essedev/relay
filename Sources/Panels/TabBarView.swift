import SwiftUI
import WorkspaceModel

/// Tab bar del workspace selezionato: i terminali del progetto, gestiti a tab. Pannello SwiftUI
/// isolato, montato sopra l'area del terminale (che è AppKit). Colori derivati dal tema corrente.
public struct TabBarView: View {
    let store: WorkspaceStore
    let settings: AppSettings

    public init(store: WorkspaceStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        return Group {
            if let workspace = store.selectedWorkspace {
                content(for: workspace, colors: colors)
            } else {
                Color.clear
            }
        }
        .frame(height: Theme.Metrics.tabBarHeight)
        .background(colors.background)
    }

    private func content(for workspace: Workspace, colors: ChromeColors) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(workspace.tabs) { tab in
                    tabItem(tab, in: workspace, colors: colors)
                }
                Button { store.addTab(to: workspace) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(colors.secondary)
                .help("New tab")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.sm)
        }
    }

    private func tabItem(
        _ tab: WorkspaceModel.Tab,
        in workspace: Workspace,
        colors: ChromeColors
    ) -> some View {
        let selected = tab.id == workspace.selectedTabID
        return HStack(spacing: Theme.Spacing.xs) {
            AgentBadge(kind: .forTab(tab), colors: colors)
            Text(tab.title)
                .font(Theme.Typography.tab)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
            Button { store.closeTab(tab.id, in: workspace) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(colors.secondary)
            .opacity(workspace.tabs.count > 1 ? 1 : 0)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(selected ? colors.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .contentShape(Rectangle())
        .onTapGesture { store.selectTab(tab.id, in: workspace) }
    }
}
