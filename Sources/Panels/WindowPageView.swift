import SwiftUI
import WorkspaceModel

/// Le azioni delle pagine, eseguite dal composition root: aprire e chiudere progetti tocca le
/// surface e le finestre, che le pagine non vedono.
public struct PageActions {
    /// Porta in vista una sessione: progetto, tab e finestra.
    public var openSession: (Workspace, WorkspaceModel.Tab) -> Void
    /// Riapre (o seleziona) un progetto, nella sua finestra.
    public var openProject: (Workspace) -> Void
    /// Chiude un progetto, con conferma se c'è lavoro in corso.
    public var closeProject: (Workspace) -> Void
    /// Chiude più progetti fermi insieme (una conferma sola).
    public var closeProjects: ([Workspace]) -> Void
    /// Crea un progetto nuovo (sceglie la cartella).
    public var newProject: () -> Void
    /// L'ultima riga dell'agente in una tab, se il suo terminale è vivo.
    public var peek: (UUID) -> String?

    public init(
        openSession: @escaping (Workspace, WorkspaceModel.Tab) -> Void,
        openProject: @escaping (Workspace) -> Void,
        closeProject: @escaping (Workspace) -> Void,
        closeProjects: @escaping ([Workspace]) -> Void,
        newProject: @escaping () -> Void,
        peek: @escaping (UUID) -> String?
    ) {
        self.openSession = openSession
        self.openProject = openProject
        self.closeProject = closeProject
        self.closeProjects = closeProjects
        self.newProject = newProject
        self.peek = peek
    }
}

/// La pagina che una finestra mostra al posto dei terminali (`RelayWindow.page`), con la sua strip
/// del titolo: trascinabile come la title bar, alla stessa altezza dei semafori. Senza progetti
/// aperti la finestra mostra Home anche se la pagina dice altro: non c'è un terminale da mostrare.
public struct WindowPageView: View {
    let store: WorkspaceStore
    let settings: AppSettings
    let windowID: UUID
    let actions: PageActions

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        windowID: UUID,
        actions: PageActions
    ) {
        self.store = store
        self.settings = settings
        self.windowID = windowID
        self.actions = actions
    }

    /// La pagina effettiva: quella chiesta, o Home se la finestra non ha un progetto da mostrare.
    public static func effectivePage(_ store: WorkspaceStore, windowID: UUID) -> WindowPage {
        let page = store.windows.first { $0.id == windowID }?.page ?? .workspace
        if page == .workspace, store.selectedWorkspace(in: windowID) == nil { return .home }
        return page
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        let page = Self.effectivePage(store, windowID: windowID)
        VStack(spacing: 0) {
            Text(page == .projects ? "Projects" : "Home")
                .font(Theme.Typography.windowTitle)
                .foregroundStyle(colors.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Metrics.titleBarHeight)
                .overlay(WindowDragArea())
            switch page {
            case .projects:
                ProjectsView(
                    store: store,
                    settings: settings,
                    onOpenProject: actions.openProject,
                    onCloseProject: actions.closeProject,
                    onNewProject: actions.newProject
                )
            case .home, .workspace:
                HomeView(
                    store: store,
                    settings: settings,
                    onOpenSession: actions.openSession,
                    onOpenProject: actions.openProject,
                    onCloseProjects: actions.closeProjects,
                    peek: actions.peek
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(colors.cardLight(height: 80))
        // Esc torna ai terminali, se c'è un progetto da mostrare.
        .onExitCommand {
            guard store.selectedWorkspace(in: windowID) != nil else { return }
            store.windows.first { $0.id == windowID }?.page = .workspace
        }
    }
}
