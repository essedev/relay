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
/// La struttura a schermo (righe di primo livello, card dei gruppi, sezione Archive) è srotolata in
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
    /// Sposta un workspace in una finestra nuova: la `NSWindow` la crea il composition root.
    let onMoveWorkspaceToNewWindow: (Workspace) -> Void
    /// Rigenera il nome del workspace. Non è `store.markNameRegenerable`: quello lo rimette solo in
    /// coda al poll passivo della nomina automatica, che su un workspace fermo non scatta mai. Il
    /// composition root ha il `NamingController`, che nomina subito e riporta l'eventuale
    /// fallimento.
    let onRegenerateName: (Workspace) -> Void
    /// Config della pill di aggiornamento (sopra la sezione Archive). `nil` = niente pill (bundle
    /// assente / test): la sidebar non dipende dalla rete né dal composition root.
    let updateConfig: SidebarUpdateConfig?
    /// Drag di una tab da una strip verso queste righe. La sidebar ci registra i bersagli e ne
    /// legge quello sotto il puntatore; `nil` = nessun drop cross-workspace (test, preview).
    let tabDrag: TabDragSession?

    /// Coordinate space unico della sidebar: lista principale e archivio ci misurano dentro le
    /// proprie righe, così il drag può attraversarli (vedi `SidebarReorder`).
    static let space = "sidebar"

    // Stato del riordino. Il gesto vive in un @GestureState: si azzera da solo (animato) anche se
    // il drag viene annullato. La struttura visiva è congelata per la durata del gesto
    // (`frozenItems`/`frozenArchived`): un evento agente può bumpare un workspace, e senza
    // snapshot rimescolerebbe righe e frame sotto il puntatore.
    @GestureState(resetTransaction: Transaction(animation: .easeInOut(duration: 0.2)))
    var drag = SidebarDragState()
    @State var frames: [Int: CGRect] = [:]
    @State var frozenItems: [SidebarItem]?
    @State var frozenArchived: [Workspace]?
    /// Altezza del contenuto archiviato: la sezione Archive si dimensiona su questa, cappata a metà
    /// sidebar (poi scroll interno).
    @State var archivedHeight: CGFloat = 0
    /// Finestre visibili dei due ScrollView (lista e archivio) nello space della sidebar: una riga
    /// scrollata fuori conserva il suo frame, che senza ritaglio finirebbe a coprire l'area di un
    /// altro contenitore e accetterebbe drop che a schermo non esistono.
    @State var listViewport: CGRect = .zero
    @State var archiveViewport: CGRect = .zero

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        windowID: UUID,
        onNewWorkspace: @escaping () -> Void,
        onCloseWorkspace: @escaping (Workspace) -> Void,
        onMoveWorkspaceToNewWindow: @escaping (Workspace) -> Void,
        onRegenerateName: @escaping (Workspace) -> Void,
        updateConfig: SidebarUpdateConfig? = nil,
        tabDrag: TabDragSession? = nil
    ) {
        self.store = store
        self.settings = settings
        self.windowID = windowID
        self.onNewWorkspace = onNewWorkspace
        self.onCloseWorkspace = onCloseWorkspace
        self.onMoveWorkspaceToNewWindow = onMoveWorkspaceToNewWindow
        self.onRegenerateName = onRegenerateName
        self.updateConfig = updateConfig
        self.tabDrag = tabDrag
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        let items = frozenItems ?? store.sidebarItems(in: windowID)
        let archived = frozenArchived ?? store.archivedWorkspaces(in: windowID)
        let plan = SidebarLayout.plan(
            items: items.map(descriptor),
            archived: archived.map(\.id),
            archiveExpanded: settings.archiveExpanded
        )
        // GeometryReader per il tetto della sezione Archive (~metà sidebar): la lista principale
        // prende il resto. Split verticale, non overlay: le due aree coesistono a vista, così il
        // drag tra loro è possibile e nulla resta nascosto dietro.
        return GeometryReader { proxy in
            VStack(spacing: 0) {
                trafficLightsStrip
                workspacesHeader(colors)
                list(items, plan: plan, colors: colors)
                if let updateConfig {
                    UpdateBanner(config: updateConfig, colors: colors)
                }
                archiveSection(
                    archived, plan: plan, colors: colors, maxListHeight: proxy.size.height * 0.5
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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
            frozenArchived = idle ? nil : store.archivedWorkspaces(in: windowID)
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
            case let .workspace(id), let .member(id, _), let .archived(id):
                id
            case .groupHeader, .groupTail, .archiveHeader:
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

    private func workspacesHeader(_ colors: ChromeColors) -> some View {
        HStack {
            Text("Workspaces")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(colors.secondary)
            Spacer()
            Button(action: onNewWorkspace) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(colors.secondary)
            .help("New workspace")
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
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
        viewport: Viewport = .list,
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
                    registerDropTarget(dragged, frame: $1, viewport: viewport)
                },
                perform: { performDrop(dragged, at: $0, plan: plan) }
            ))
    }

    /// Quale dei due ScrollView ospita una riga: serve a ritagliarne il frame quando si registra
    /// come bersaglio del drop.
    enum Viewport {
        case list
        case archive
    }

    /// Registra (o toglie) una riga fra i bersagli del drop di una tab. Solo i workspace:
    /// rilasciare
    /// una sessione sull'header di una card non ha un significato ovvio, meglio nessun bersaglio
    /// che uno che indovina. Il frame viene ritagliato al suo ScrollView e scartato se la riga è
    /// visibile per meno di metà: un bersaglio a filo di bordo è una promessa che l'occhio non
    /// vede.
    private func registerDropTarget(
        _ dragged: SidebarDrop.Dragged, frame: CGRect, viewport: Viewport
    ) {
        guard let tabDrag, case let .workspace(id) = dragged else { return }
        let clip = viewport == .archive ? archiveViewport : listViewport
        let visible = frame.intersection(clip)
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

    /// Riga workspace completa (callback allo store), condivisa da lista principale, card dei
    /// gruppi e sezione Archive.
    func makeRow(_ workspace: Workspace, colors: ChromeColors) -> WorkspaceRow {
        WorkspaceRow(
            workspace: workspace,
            selected: workspace.id == store.selectedWorkspace(in: windowID)?.id,
            dropTargeted: tabDrag?.target == workspace.id,
            colors: colors,
            groupMenu: groupMenu(for: workspace),
            onSelect: { store.selectWorkspace(workspace.id) },
            onTogglePin: { store.togglePin(workspace.id) },
            onRename: { store.renameWorkspace(workspace.id, to: $0) },
            onRegenerateName: { onRegenerateName(workspace) },
            onToggleUnread: { toggleUnread(workspace) },
            onToggleArchive: { store.toggleArchive(workspace.id) },
            // Solo se la finestra ha altro da mostrare dopo: altrimenti resterebbe vuota.
            onMoveToNewWindow: store.workspaces(in: windowID).count > 1
                ? { onMoveWorkspaceToNewWindow(workspace) }
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
