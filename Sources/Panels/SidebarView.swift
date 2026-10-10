import SwiftUI
import WorkspaceModel

/// Sidebar: elenco dei workspace con selezione, pin, gruppi, archivio e riordino. Pannello SwiftUI
/// isolato, disaccoppiato dal view tree del terminale. La creazione di un workspace è delegata
/// all'app (`onNewWorkspace`), che sceglie la cartella progetto; la chiusura a `onCloseWorkspace`,
/// che può chiedere conferma se una tab è occupata. Colori derivati dal tema corrente.
///
/// Liste custom (`VStack`, non `List`): la `List` di macOS disegna un highlight full-size di
/// sistema sotto la riga bersaglio del menu contestuale, fuori dal design flat a tema. Con la
/// VStack controlliamo noi selezione, hover e menu; il riordino è drag & drop esplicito. Niente
/// `LazyVStack` nemmeno nella lista principale: le righe smontate non misurano il proprio frame, e
/// il drag ha bisogno del frame di **tutte** le righe, comprese quelle fuori vista.
///
/// In cima la navigazione (ricerca `⌘P`, Home, Projects), sotto i soli progetti **aperti**: i
/// chiusi
/// stanno nel catalogo (`docs/features/projects.md`). La struttura a schermo (righe di primo
/// livello, card dei gruppi) è srotolata in
/// un piano piatto di righe e slot (`SidebarLayout`), che è ciò su cui il drag calcola; il
/// rendering resta annidato, così le card possono disegnarsi attorno ai loro membri.
public struct SidebarView: View {
    let store: WorkspaceStore
    let settings: AppSettings
    /// La finestra che ospita la sidebar: elenca solo **i suoi** workspace (le finestre li
    /// partizionano), e la riga selezionata è quella che questa finestra mostra.
    let windowID: UUID
    let onNewWorkspace: () -> Void
    let onCloseWorkspace: (Workspace) -> Void
    /// Chiude un progetto: il composition root chiede conferma se c'è lavoro in corso e butta le
    /// surface dopo aver marcato le tab (vedi `WorkspaceStore.setClosed`).
    let onCloseProject: (Workspace) -> Void
    let onDeactivateSessions: (Workspace) -> Void
    /// Sposta un workspace in una finestra nuova: la `NSWindow` la crea il composition root.
    let onMoveWorkspaceToNewWindow: (Workspace) -> Void
    /// Rigenera il nome del workspace. Non è `store.markNameRegenerable`: quello lo rimette solo in
    /// coda al poll passivo della nomina automatica, che su un workspace fermo non scatta mai. Il
    /// composition root ha il `NamingController`, che nomina subito e riporta l'eventuale
    /// fallimento.
    let onRegenerateName: (Workspace) -> Void
    /// Apre la palette "Go to project" (`⌘P`).
    let onShowPalette: () -> Void
    /// Mostra una pagina (Home, Projects) nella finestra: il composition root applica la
    /// decadenza dei sospesi all'apertura di Home.
    let onShowPage: (WindowPage) -> Void
    /// Config della pill di aggiornamento (in fondo alla sidebar). `nil` = niente pill (bundle
    /// assente / test): la sidebar non dipende dalla rete né dal composition root.
    let updateConfig: SidebarUpdateConfig?
    /// Drag di una tab da una strip verso queste righe. La sidebar ci registra i bersagli e ne
    /// legge quello sotto il puntatore; `nil` = nessun drop cross-workspace (test, preview).
    let tabDrag: TabDragSession?

    /// Coordinate space unico della sidebar: le righe ci misurano dentro, così il drag attraversa
    /// le card e la lista (vedi `SidebarReorder`).
    static let space = "sidebar"

    // Stato del riordino. Il gesto vive in un @GestureState: si azzera da solo (animato) anche se
    // il drag viene annullato. La struttura visiva è congelata per la durata del gesto
    // (`frozenItems`): un evento agente può bumpare un workspace, e senza
    // snapshot rimescolerebbe righe e frame sotto il puntatore.
    @GestureState(resetTransaction: Transaction(animation: .easeInOut(duration: 0.2)))
    var drag = SidebarDragState()
    @State var frames: [Int: CGRect] = [:]
    @State var frozenItems: [SidebarItem]?
    /// Finestra visibile della lista nello space della sidebar: una riga scrollata fuori conserva
    /// il suo frame, che senza ritaglio accetterebbe drop che a schermo non esistono.
    @State var listViewport: CGRect = .zero

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        windowID: UUID,
        onNewWorkspace: @escaping () -> Void,
        onCloseWorkspace: @escaping (Workspace) -> Void,
        onCloseProject: @escaping (Workspace) -> Void,
        onDeactivateSessions: @escaping (Workspace) -> Void,
        onMoveWorkspaceToNewWindow: @escaping (Workspace) -> Void,
        onRegenerateName: @escaping (Workspace) -> Void,
        onShowPalette: @escaping () -> Void = {},
        onShowPage: @escaping (WindowPage) -> Void = { _ in },
        updateConfig: SidebarUpdateConfig? = nil,
        tabDrag: TabDragSession? = nil
    ) {
        self.store = store
        self.settings = settings
        self.windowID = windowID
        self.onNewWorkspace = onNewWorkspace
        self.onCloseWorkspace = onCloseWorkspace
        self.onCloseProject = onCloseProject
        self.onDeactivateSessions = onDeactivateSessions
        self.onMoveWorkspaceToNewWindow = onMoveWorkspaceToNewWindow
        self.onRegenerateName = onRegenerateName
        self.onShowPalette = onShowPalette
        self.onShowPage = onShowPage
        self.updateConfig = updateConfig
        self.tabDrag = tabDrag
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        let items = frozenItems ?? store.sidebarItems(in: windowID)
        let plan = SidebarLayout.plan(items: items.map(descriptor))
        return VStack(spacing: 0) {
            trafficLightsStrip
            SidebarNav(
                store: store,
                windowID: windowID,
                colors: colors,
                onShowPalette: onShowPalette,
                onShowPage: onShowPage
            )
            openHeader(colors)
            list(items, plan: plan, colors: colors)
            if let updateConfig {
                UpdateBanner(config: updateConfig, colors: colors)
            }
            footer(colors)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .frame(minWidth: 200)
        .background(colors.background)
        .coordinateSpace(.named(Self.space))
        // Riga in volo e linea di inserimento vivono qui, sopra **tutta** la sidebar: dentro una
        // ScrollView verrebbero clippate al bordo proprio mentre esci dal contenitore.
        .overlay(alignment: .topLeading) {
            SidebarInsertionLine(
                insertion: drag.dragged == nil ? nil : drag.insertion,
                frames: frames,
                count: plan.count,
                color: colors.accent,
                indent: insertionIndent(plan: plan)
            )
        }
        .overlay(alignment: .topLeading) { flyingRow(colors: colors) }
        // Struttura congelata mentre un drag è in corso, **anche** quello di una tab che arriva da
        // una strip: lì il puntatore mira a una riga, e un bump da attività non vista la
        // sposterebbe sotto le mani un istante prima del rilascio.
        .onChange(of: drag.dragged == nil && tabDrag?.payload == nil) { _, idle in
            frozenItems = idle ? nil : store.sidebarItems(in: windowID)
        }
        // Bersagli del drop di una tab (vedi TabDragSession): la sidebar intera fa da guardia (un
        // rilascio fuori di qui non sposta niente), le singole righe si registrano in `draggable`.
        .windowRect { tabDrag?.setSidebarRect($0) }
        .onChange(of: plan.rows) { _, rows in
            tabDrag?.pruneTargets(keeping: Self.workspaceIDs(in: rows))
        }
    }

    /// I workspace che il piano mostra davvero: i membri di una card chiusa non ci sono, e non
    /// devono restare bersagli.
    static func workspaceIDs(in rows: [SidebarLayout.Row]) -> Set<UUID> {
        Set(rows.compactMap { row in
            switch row {
            case let .workspace(id), let .member(id, _):
                id
            case .groupHeader, .groupTail:
                nil
            }
        })
    }

    /// Descrittore puro di un elemento per il piano delle righe (`SidebarLayout` non conosce i tipi
    /// osservabili del model).
    func descriptor(_ item: SidebarItem) -> SidebarLayout.Item {
        switch item {
        case let .workspace(workspace):
            SidebarLayout.Item(id: workspace.id, kind: .workspace, pinned: workspace.pinned)
        case let .group(group, members):
            SidebarLayout.Item(
                id: group.id,
                kind: .group(members: members.map(\.id), collapsed: group.collapsed),
                pinned: group.pinned
            )
        }
    }

    /// Riga dei semafori (full-size content view): vuota e pulita, zona di drag e doppio click
    /// (zoom finestra). Il toggle della sidebar è un accessory della title bar (posizione fissa).
    private var trafficLightsStrip: some View {
        WindowDragArea()
            .frame(height: Theme.Metrics.titleBarHeight)
    }

    /// Intestazione della lista: i progetti aperti, quanti sono, e il `+` per uno nuovo.
    private func openHeader(_ colors: ChromeColors) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Open")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(colors.secondary)
            Spacer()
            Text("\(store.orderedWorkspaces(in: windowID).count)")
                .font(Theme.Typography.subtitle)
                .foregroundStyle(colors.secondary.opacity(0.7))
            Button(action: onNewWorkspace) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(colors.secondary)
            .help("New project")
        }
        .padding(.horizontal, Theme.Spacing.md + Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xs)
    }

    /// Piede: quanti aperti e quanti chiusi, cioè quanto lavoro vive e quanto aspetta nel catalogo.
    private func footer(_ colors: ChromeColors) -> some View {
        let open = store.workspaces.count { !$0.closed }
        let closed = store.workspaces.count - open
        return Text("\(open) open, \(closed) closed")
            .font(Theme.Typography.subtitle)
            .foregroundStyle(colors.secondary.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md + Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.sm)
    }

    /// Lista principale: righe libere e card dei gruppi. Il padding orizzontale insetta la pill di
    /// selezione dai bordi (`sm`); il contenuto della riga aggiunge `xs` così allinea con l'header
    /// (`sm + xs = md`).
    private func list(
        _ items: [SidebarItem], plan: SidebarLayout.Plan, colors: ChromeColors
    ) -> some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(items) { item in
                    switch item {
                    case let .workspace(workspace):
                        draggable(.workspace(workspace.id), plan: plan) {
                            makeRow(workspace, colors: colors)
                        }
                    case let .group(group, members):
                        groupCard(group, members: members, plan: plan, colors: colors)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .animation(.easeInOut(duration: 0.2), value: plan.rows)
        }
        .scrollContentBackground(.hidden)
        .onGeometryChange(
            for: CGRect.self,
            of: { $0.frame(in: .named(Self.space)) },
            action: { listViewport = $0 }
        )
        .layoutPriority(1) // la lista principale tiene il flex; l'archivio prende il resto
    }

    /// Avvolge una riga nella meccanica di drag: indice nel piano, misura del frame nel coordinate
    /// space condiviso, gesto e drop. `row` esplicito quando la riga non è di primo livello (membro
    /// di una card, header di gruppo, archiviato).
    @ViewBuilder
    func draggable(
        _ dragged: SidebarDrop.Dragged,
        plan: SidebarLayout.Plan,
        row: SidebarLayout.Row? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let target = row ?? defaultRow(for: dragged)
        let index = plan.index(of: target)
        content()
            .sidebarReorderRow(SidebarRowConfig(
                dragged: dragged,
                index: index,
                space: Self.space,
                frames: frames,
                plan: plan,
                drag: $drag,
                state: drag,
                onFrame: {
                    frames[$0] = $1
                    registerDropTarget(dragged, frame: $1)
                },
                perform: { performDrop(dragged, at: $0, plan: plan) }
            ))
    }

    /// Registra (o toglie) una riga fra i bersagli del drop di una tab. Solo i workspace:
    /// rilasciare
    /// una sessione sull'header di una card non ha un significato ovvio, meglio nessun bersaglio
    /// che uno che indovina. Il frame viene ritagliato al suo ScrollView e scartato se la riga è
    /// visibile per meno di metà: un bersaglio a filo di bordo è una promessa che l'occhio non
    /// vede.
    private func registerDropTarget(
        _ dragged: SidebarDrop.Dragged, frame: CGRect
    ) {
        guard let tabDrag, case let .workspace(id) = dragged else { return }
        let visible = frame.intersection(listViewport)
        if visible.isNull || visible.height < frame.height / 2 {
            tabDrag.clearTarget(id)
        } else {
            tabDrag.setTarget(id, frame: visible)
        }
    }

    func defaultRow(for dragged: SidebarDrop.Dragged) -> SidebarLayout.Row {
        switch dragged {
        case let .workspace(id): .workspace(id)
        case let .group(id): .groupHeader(id)
        }
    }

    /// Riga workspace completa (callback allo store), condivisa da lista principale e card dei
    /// gruppi.
    func makeRow(_ workspace: Workspace, colors: ChromeColors) -> WorkspaceRow {
        WorkspaceRow(
            workspace: workspace,
            // Selezionata solo se la finestra mostra davvero i suoi terminali: con Home o Projects
            // su, una riga accesa indicherebbe un posto in cui non sei.
            selected: workspace.id == store.selectedWorkspace(in: windowID)?.id
                && WindowPageView.effectivePage(store, windowID: windowID) == .workspace,
            dropTargeted: tabDrag?.target == workspace.id,
            colors: colors,
            groupMenu: groupMenu(for: workspace),
            // Un chiuso non si "seleziona": lo si riapre, o la finestra mostrerebbe un progetto
            // senza terminali vivi.
            onSelect: { store.openProject(workspace.id) },
            onTogglePin: { store.togglePin(workspace.id) },
            onRename: { store.renameWorkspace(workspace.id, to: $0) },
            onRegenerateName: { onRegenerateName(workspace) },
            onToggleUnread: { toggleUnread(workspace) },
            onToggleClosed: {
                if workspace.closed { store.setClosed(workspace.id, false) } else {
                    onCloseProject(workspace)
                }
            },
            // Solo se la finestra ha altro da mostrare dopo: altrimenti resterebbe vuota.
            onMoveToNewWindow: store.workspaces(in: windowID).count > 1
                ? { onMoveWorkspaceToNewWindow(workspace) }
                : nil,
            onDeactivateSessions: workspace.tabs.contains { $0.resume != nil }
                ? { onDeactivateSessions(workspace) }
                : nil,
            onClose: { onCloseWorkspace(workspace) }
        )
    }

    /// Toggle manuale del marker di attenzione dal menu contestuale: agisce sulla tab selezionata
    /// del workspace (il marker vive per-tab).
    private func toggleUnread(_ workspace: Workspace) {
        guard let tabID = workspace.selectedTab?.id else { return }
        store.toggleUnread(tabID)
    }
}
