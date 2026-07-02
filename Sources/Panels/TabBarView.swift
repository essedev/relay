import SwiftUI
import WorkspaceModel

/// Tab bar del workspace selezionato: i terminali del progetto, gestiti a tab. Pannello SwiftUI
/// isolato, montato sopra l'area del terminale (che è AppKit). Colori derivati dal tema corrente.
/// La chiusura è delegata all'app (`onCloseTab`), che può chiedere conferma se la tab è occupata.
public struct TabBarView: View {
    let store: WorkspaceStore
    let settings: AppSettings
    let onCloseTab: (WorkspaceModel.Tab, Workspace) -> Void

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        onCloseTab: @escaping (WorkspaceModel.Tab, Workspace) -> Void
    ) {
        self.store = store
        self.settings = settings
        self.onCloseTab = onCloseTab
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
                    TabItemView(
                        tab: tab,
                        selected: tab.id == workspace.selectedTabID,
                        colors: colors,
                        onSelect: { store.selectTab(tab.id, in: workspace) },
                        onClose: { onCloseTab(tab, workspace) }
                    )
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
}

/// Singola tab. View separata per lo stato di hover locale: la x compare su hover o sulla tab
/// selezionata, così è sempre raggiungibile (anche con una sola tab) senza affollare la barra.
private struct TabItemView: View {
    let tab: WorkspaceModel.Tab
    let selected: Bool
    let colors: ChromeColors
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            AgentBadge(kind: .forTab(tab), colors: colors)
            Text(tab.title)
                .font(Theme.Typography.tab)
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(colors.secondary)
            .opacity(hovered || selected ? 1 : 0)
            .help("Close tab")
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(selected ? colors.selection : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
    }
}
