import SwiftUI
import WorkspaceModel

/// Strip del titolo contestuale in cima al right pane: centrata sul body (non sull'intera
/// finestra), solo testo. Contenuto da `WindowTitle`: nome chat se c'è Claude (titolo OSC),
/// `user@host:path` dalla shell, altrimenti cwd/workspace.
public struct ContextTitleBar: View {
    let store: WorkspaceStore
    let settings: AppSettings

    public init(store: WorkspaceStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        let workspace = store.selectedWorkspace
        return Text(WindowTitle.compose(workspace: workspace, tab: workspace?.selectedTab))
            .font(Theme.Typography.windowTitle)
            .foregroundStyle(colors.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Metrics.titleBarHeight)
            .background(colors.background)
            // Trascinamento finestra + doppio click (zoom) come una title bar: la strip è solo
            // testo, l'area copre tutto sopra di essa.
            .overlay(WindowDragArea())
    }
}
