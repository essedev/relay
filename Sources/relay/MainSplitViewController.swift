import AppKit
import Observation
import Panels
import SwiftUI
import TerminalEngine
import WorkspaceModel

/// Split principale: sidebar (SwiftUI in NSHostingController) + area di lavoro a destra.
@MainActor
final class MainSplitViewController: NSSplitViewController {
    private let settings: AppSettings
    private var sidebarItem: NSSplitViewItem!

    init(
        store: WorkspaceStore,
        settings: AppSettings,
        engine: TerminalEngine,
        onNewWorkspace: @escaping () -> Void
    ) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)

        let sidebar = NSHostingController(
            rootView: SidebarView(
                store: store,
                settings: settings,
                onNewWorkspace: onNewWorkspace,
                // Al doppio click la finestra è già key (il primo click la attiva).
                onTitleBarDoubleClick: { TitleBarActions.handleDoubleClick(in: NSApp.keyWindow) },
                onToggleSidebar: { settings.toggleSidebar() }
            )
        )
        // L'header della sidebar vive sulla riga dei semafori (full-size content view): niente
        // safe area, il layout la gestisce con l'inset esplicito.
        sidebar.safeAreaRegions = []
        // Item normale, non `sidebarWithViewController:`: su macOS 26 quello stila la sidebar come
        // pannello glass flottante (box, materiale, margini), in conflitto col design flat themed.
        let item = NSSplitViewItem(viewController: sidebar)
        item.minimumThickness = 200
        item.maximumThickness = 340
        // Il resize della finestra va al body: la sidebar tiene la sua larghezza.
        item.holdingPriority = NSLayoutConstraint.Priority(260)
        item.canCollapse = true
        sidebarItem = item
        addSplitViewItem(item)

        let right = RightPaneController(store: store, settings: settings, engine: engine)
        addSplitViewItem(NSSplitViewItem(viewController: right))

        observeSidebarState()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("MainSplitViewController is programmatic-only")
    }

    /// Lo stato del collapse vive in `AppSettings` (persistito); qui lo si applica all'item,
    /// animato. Si ri-arma sui cambi (Observation).
    private func observeSidebarState() {
        withObservationTracking {
            let collapsed = settings.sidebarCollapsed
            if sidebarItem.isCollapsed != collapsed {
                sidebarItem.animator().isCollapsed = collapsed
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSidebarState() }
        }
    }
}
