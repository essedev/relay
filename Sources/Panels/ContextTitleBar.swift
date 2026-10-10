import SwiftUI
import WorkspaceModel

/// Strip del titolo contestuale in cima al right pane: centrata sul body (non sull'intera
/// finestra), solo testo. Contenuto da `WindowTitle`: nome chat se c'è Claude (titolo OSC),
/// `user@host:path` dalla shell, altrimenti cwd/workspace.
public struct ContextTitleBar: View {
    let store: WorkspaceStore
    let settings: AppSettings
    /// La finestra che ospita la strip: mostra il titolo del workspace **che questa finestra
    /// mostra**, non di quello globale (due finestre hanno due titoli).
    let windowID: UUID

    public init(store: WorkspaceStore, settings: AppSettings, windowID: UUID) {
        self.store = store
        self.settings = settings
        self.windowID = windowID
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        let workspace = store.selectedWorkspace(in: windowID)
        return Text(WindowTitle.compose(workspace: workspace, tab: workspace?.selectedTab))
            .font(Theme.Typography.windowTitle)
            .foregroundStyle(colors.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Metrics.titleBarHeight)
            // La luce in cima alla card del contenuto: si spegne sul fondo del tema al bordo della
            // strip, così le tab e il terminale sotto restano sul colore del tema.
            .background(colors.cardLight(height: Theme.Metrics.titleBarHeight))
            // Trascinamento finestra + doppio click (zoom) come una title bar: la strip è solo
            // testo, l'area copre tutto sopra di essa.
            .overlay(WindowDragArea())
    }
}
