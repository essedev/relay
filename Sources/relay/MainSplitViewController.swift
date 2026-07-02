import AppKit
import Panels
import SwiftUI
import TerminalEngine
import WorkspaceModel

/// Split principale: sidebar (SwiftUI in NSHostingController) + area di lavoro a destra.
@MainActor
final class MainSplitViewController: NSSplitViewController {
    init(
        store: WorkspaceStore,
        settings: AppSettings,
        engine: TerminalEngine,
        onNewWorkspace: @escaping () -> Void
    ) {
        super.init(nibName: nil, bundle: nil)

        let sidebar = NSHostingController(
            rootView: SidebarView(
                store: store,
                settings: settings,
                onNewWorkspace: onNewWorkspace,
                // Al doppio click la finestra è già key (il primo click la attiva).
                onTitleBarDoubleClick: { TitleBarActions.handleDoubleClick(in: NSApp.keyWindow) }
            )
        )
        // L'header della sidebar vive sulla riga dei semafori (full-size content view): niente
        // safe area, il layout la gestisce con l'inset esplicito.
        sidebar.safeAreaRegions = []
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 340
        addSplitViewItem(sidebarItem)

        let right = RightPaneController(store: store, settings: settings, engine: engine)
        addSplitViewItem(NSSplitViewItem(viewController: right))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("MainSplitViewController is programmatic-only")
    }
}
