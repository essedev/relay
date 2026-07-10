import SwiftUI
import WorkspaceModel

/// Le azioni della strip che risalgono al composition root: quelle che chiedono conferma (chiusure
/// con processi vivi), risolvono la cwd dalla shell viva (nuove tab, split) o assegnano nomi
/// placeholder (nuovi workspace). Il resto (selezione, rename, riordino) parla con lo store
/// direttamente.
public struct PaneTabBarActions {
    public var newTab: (UUID, Workspace) -> Void
    public var splitPane: (UUID, SplitAxis, Workspace) -> Void
    public var closePane: (UUID, Workspace) -> Void
    public var closeTab: (WorkspaceModel.Tab, Workspace) -> Void
    public var moveTabToNewWorkspace: (WorkspaceModel.Tab, Workspace) -> Void

    public init(
        newTab: @escaping (UUID, Workspace) -> Void,
        splitPane: @escaping (UUID, SplitAxis, Workspace) -> Void,
        closePane: @escaping (UUID, Workspace) -> Void,
        closeTab: @escaping (WorkspaceModel.Tab, Workspace) -> Void,
        moveTabToNewWorkspace: @escaping (WorkspaceModel.Tab, Workspace) -> Void
    ) {
        self.newTab = newTab
        self.splitPane = splitPane
        self.closePane = closePane
        self.closeTab = closeTab
        self.moveTabToNewWorkspace = moveTabToNewWorkspace
    }
}

/// La strip di tab di **un pane** (modello cmux): le sue tab a sinistra, l'action lane a destra
/// (nuova tab, split right, split down). Ogni pane ne monta una; click su una tab = selezione nel
/// pane + focus al pane; click sullo spazio vuoto = focus; doppio click = nuova tab.
///
/// Pannello SwiftUI isolato, montato dentro la `PaneView` (AppKit) via factory del composition
/// root. Colori dal tema corrente; la barra del pane non focused attenua i suoi segnali.
public struct PaneTabBar: View {
    let store: WorkspaceStore
    let settings: AppSettings
    /// La finestra che ospita il pane: la strip mostra il workspace **di questa finestra**.
    let windowID: UUID
    /// Il pane di cui questa strip mostra le tab (`SplitPane.id`).
    let paneID: UUID
    let actions: PaneTabBarActions

    // Stato del riordino via drag & drop (vedi Reorderable), in un @GestureState che si azzera
    // da solo anche a gesto annullato. Il riordino vive dentro la strip: niente segmenti.
    @GestureState(resetTransaction: Transaction(animation: .easeInOut(duration: 0.2)))
    private var drag = ReorderDragState()
    @State private var tabFrames: [Int: CGRect] = [:]
    @State private var laneHovered = false

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        windowID: UUID,
        paneID: UUID,
        actions: PaneTabBarActions
    ) {
        self.store = store
        self.settings = settings
        self.windowID = windowID
        self.paneID = paneID
        self.actions = actions
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        let workspace = store.selectedWorkspace(in: windowID)
        let pane = workspace?.layout.pane(paneID)
        return Group {
            if let workspace, let pane {
                content(for: pane, in: workspace, colors: colors)
            } else {
                // Il pane sta uscendo di scena (workspace cambiato, pane chiuso): la view muore
                // col prossimo reconcile.
                Color.clear
            }
        }
        .frame(height: Theme.Metrics.tabBarHeight)
    }

    private func content(
        for pane: SplitPane, in workspace: Workspace, colors: ChromeColors
    ) -> some View {
        let focusedPane = workspace.focusedPaneID == paneID
        let tabs = pane.tabIDs.compactMap { workspace.tab($0) }
        return HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                tabsRow(
                    tabs, pane: pane, workspace: workspace,
                    focusedPane: focusedPane, colors: colors
                )
            }
            actionLane(in: workspace, focusedPane: focusedPane, colors: colors)
        }
        .background(colors.background)
        .contentShape(Rectangle())
        // Prima il doppio (nuova tab), poi il singolo (focus): SwiftUI li discrimina da solo.
        .onTapGesture(count: 2) { actions.newTab(paneID, workspace) }
        .onTapGesture { store.focusPane(paneID, in: workspace) }
    }

    private func tabsRow(
        _ tabs: [WorkspaceModel.Tab],
        pane: SplitPane,
        workspace: Workspace,
        focusedPane: Bool,
        colors: ChromeColors
    ) -> some View {
        let space = "pane-strip-\(paneID.uuidString)"
        return HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                PaneTabItem(
                    tab: tab,
                    selected: tab.id == pane.selectedTabID,
                    focusedPane: focusedPane,
                    // Spostarla in split richiede una compagna che tenga vivo il pane; idem
                    // spostarla in un nuovo workspace (svuoterebbe questo).
                    canLeavePane: tabs.count > 1,
                    canMoveToNewWorkspace: workspace.tabs.count > 1,
                    canClosePane: workspace.layout.paneIDs.count > 1,
                    colors: colors,
                    onSelect: { store.selectTab(tab.id, in: workspace) },
                    onRename: { store.renameTab(tab.id, in: workspace, to: $0) },
                    onToggleUnread: { store.toggleUnread(tab.id) },
                    onOpenInSplit: { store.openInSplit(tab.id, axis: $0, in: workspace) },
                    onClosePane: { actions.closePane(paneID, workspace) },
                    onMoveToNewWorkspace: { actions.moveTabToNewWorkspace(tab, workspace) },
                    onClose: { actions.closeTab(tab, workspace) }
                )
                .reorderableRow(ReorderRowConfig(
                    id: tab.id,
                    index: index,
                    axis: .horizontal,
                    space: space,
                    count: tabs.count,
                    frames: tabFrames,
                    drag: $drag,
                    state: drag,
                    perform: { performMove(of: tab.id, to: $0, tabs: tabs, in: workspace) }
                ))
            }
        }
        .reorderableContainer(ReorderContainerConfig(
            space: space,
            axis: .horizontal,
            count: tabs.count,
            frames: $tabFrames,
            insertion: drag.insertion,
            lineColor: colors.accent
        ))
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(minHeight: Theme.Metrics.tabBarHeight)
    }

    /// L'action lane del pane (pattern cmux): nuova tab, split right, split down. Piena sul pane
    /// focused o in hover, attenuata altrove: i controlli sono di *questo* pane, e la barra deve
    /// dirlo senza urlare su ogni pane a schermo.
    private func actionLane(
        in workspace: Workspace, focusedPane: Bool, colors: ChromeColors
    ) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            laneButton("plus", help: "New Tab") { actions.newTab(paneID, workspace) }
            laneButton("square.split.2x1", help: "Split Right") {
                actions.splitPane(paneID, .horizontal, workspace)
            }
            laneButton("square.split.1x2", help: "Split Down") {
                actions.splitPane(paneID, .vertical, workspace)
            }
        }
        .foregroundStyle(ChromeColors(settings.theme).secondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .opacity(focusedPane || laneHovered ? 1 : 0.45)
        .background(colors.background)
        .onHover { laneHovered = $0 }
    }

    private func laneButton(
        _ symbol: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    /// Inserisce la tab trascinata prima della tab `insertion` della strip (o in fondo). Il reset
    /// del drag lo fa la resetTransaction del @GestureState.
    private func performMove(
        of dragID: UUID, to insertion: Int, tabs: [WorkspaceModel.Tab], in workspace: Workspace
    ) {
        let targetID = insertion < tabs.count ? tabs[insertion].id : nil
        store.moveTab(dragID, before: targetID, in: workspace)
    }
}

/// Singola tab della strip. View separata per lo stato locale (hover + editing): la x compare su
/// hover o sulla tab selezionata; il rename dal menu contestuale scambia il titolo con un
/// `TextField` inline.
private struct PaneTabItem: View {
    let tab: WorkspaceModel.Tab
    /// La tab a schermo in questo pane (la selezionata della strip).
    let selected: Bool
    /// Il pane della strip ha il focus di tastiera: la selezione si mostra piena, altrove tenue.
    let focusedPane: Bool
    let canLeavePane: Bool
    let canMoveToNewWorkspace: Bool
    let canClosePane: Bool
    let colors: ChromeColors
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onToggleUnread: () -> Void
    let onOpenInSplit: (SplitAxis) -> Void
    let onClosePane: () -> Void
    let onMoveToNewWorkspace: () -> Void
    let onClose: () -> Void

    @State private var hovered = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            AgentBadge(kind: .forTab(tab), colors: colors)
            if editing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.tab)
                    .foregroundStyle(colors.foreground)
                    .frame(width: 90)
                    .focused($nameFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commit() }
                    }
                    .onAppear { DispatchQueue.main.async { nameFocused = true } }
            } else {
                Text(tab.title)
                    .font(Theme.Typography.tab)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Theme.Metrics.maxTabWidth, alignment: .leading)
            }
            CloseButton(color: colors.secondary, size: 8, help: "Close Tab", action: onClose)
                .opacity(hovered || selected ? 1 : 0)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        // Lo stato è il riempimento: piena la selezionata del pane focused, tenue quella dei pane
        // non focused, trasparenti le altre. (Un pallino confliggerebbe col badge di stato agente.)
        .background(backgroundFill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Rename…", action: beginRename)
            if canLeavePane {
                // Sposta la tab in un nuovo pane accanto, con la sua sessione viva (pattern
                // bonsplit). Nascosta se è l'unica della strip: dividerla accanto a sé stessa non
                // produce niente, e lo store lo rifiuterebbe.
                Button("Open in Split Right") { onOpenInSplit(.horizontal) }
                Button("Open in Split Down") { onOpenInSplit(.vertical) }
            }
            // Toggle manuale del marker di attenzione (metafora unread), per-tab. Solo `unseen`
            // (segnale forte, non visto) è "unread": lì offro "Mark as Read". Un `pending` è già
            // visto (quieto), quindi lo si può solo ri-alzare a forte ("Mark as Unread").
            let unreadLabel = tab.attention == .unseen ? "Mark as Read" : "Mark as Unread"
            Button(unreadLabel, action: onToggleUnread)
            if canMoveToNewWorkspace {
                // Estrae la tab in un nuovo workspace senza toccare la sessione viva (stesso
                // Tab.id -> surface intatta). Nascosta con una sola tab (sarebbe un no-op).
                Button("Move to New Workspace", action: onMoveToNewWorkspace)
            }
            Divider()
            if canClosePane {
                // Chiude il pane e tutte le sue tab (le sessioni muoiono: conferma a monte).
                Button("Close Pane", role: .destructive, action: onClosePane)
            }
            Button("Close Tab", role: .destructive, action: onClose)
        }
    }

    /// Riempimento della pill: piena per la selezionata del pane focused, tenue se il pane non ha
    /// il focus (a schermo, ma la tastiera è altrove).
    private var backgroundFill: Color {
        guard selected else { return .clear }
        return focusedPane ? colors.selection : colors.selection.opacity(0.4)
    }

    private func beginRename() {
        draft = tab.title
        editing = true
    }

    private func commit() {
        guard editing else { return }
        editing = false
        onRename(draft)
    }

    private func cancel() {
        editing = false
    }
}
