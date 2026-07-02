import SwiftUI
import WorkspaceModel

/// Strip del titolo contestuale in cima al right pane: centrata sul body (non sull'intera
/// finestra), solo testo. Contenuto da `WindowTitle`: nome chat se c'è Claude (titolo OSC),
/// `user@host:path` dalla shell, altrimenti cwd/workspace.
public struct ContextTitleBar: View {
    let store: WorkspaceStore
    let settings: AppSettings
    /// Doppio click sulla strip = comportamento title bar di macOS (zoom); gestito dall'host.
    let onDoubleClick: () -> Void
    /// Riapre la sidebar (visibile solo quando è chiusa: il suo bottone è sparito con lei).
    let onToggleSidebar: () -> Void

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        onDoubleClick: @escaping () -> Void = {},
        onToggleSidebar: @escaping () -> Void = {}
    ) {
        self.store = store
        self.settings = settings
        self.onDoubleClick = onDoubleClick
        self.onToggleSidebar = onToggleSidebar
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        let workspace = store.selectedWorkspace
        return ZStack {
            Text(WindowTitle.compose(workspace: workspace, tab: workspace?.selectedTab))
                .font(Theme.Typography.windowTitle)
                .foregroundStyle(colors.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, Theme.Spacing.lg)
            if settings.sidebarCollapsed {
                HStack {
                    Button(action: onToggleSidebar) {
                        Image(systemName: "sidebar.leading")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(colors.secondary)
                    .help("Show sidebar (⌘B)")
                    // Sidebar chiusa: i semafori stanno sopra questa strip, il bottone va dopo.
                    .padding(.leading, Theme.Metrics.trafficLightsInset)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.Metrics.titleBarHeight)
        .background(colors.background)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClick() }
    }
}
