import SwiftUI
import WorkspaceModel

/// Sidebar: elenco dei workspace con selezione, pin, riordino. Pannello SwiftUI isolato,
/// disaccoppiato dal view tree del terminale. La creazione di un workspace è delegata all'app
/// (`onNewWorkspace`), che sceglie la cartella progetto; la chiusura a `onCloseWorkspace`, che può
/// chiedere conferma se una tab è occupata. Colori derivati dal tema corrente.
///
/// Lista custom (`LazyVStack`, non `List`): la `List` di macOS disegna un highlight full-size di
/// sistema sotto la riga bersaglio del menu contestuale, fuori dal design flat a tema. Con la
/// VStack controlliamo noi selezione, hover e menu; il riordino è drag & drop esplicito.
public struct SidebarView: View {
    let store: WorkspaceStore
    let settings: AppSettings
    let onNewWorkspace: () -> Void
    let onCloseWorkspace: (Workspace) -> Void
    /// Config della pill di aggiornamento (sopra la sezione Archive). `nil` = niente pill (bundle
    /// assente / test): la sidebar non dipende dalla rete né dal composition root.
    let updateConfig: SidebarUpdateConfig?

    // Stato del riordino via drag & drop (vedi Reorderable). Il gesto vive in un @GestureState:
    // si azzera da solo (animato) anche se il drag viene annullato. L'ordine visivo è congelato
    // per la durata del gesto (`frozenOrder`): il float è derivato dallo stato agente e senza
    // snapshot un cambio di stato rimescolerebbe righe e frame sotto il puntatore.
    @GestureState(resetTransaction: Transaction(animation: .easeInOut(duration: 0.2)))
    private var drag = ReorderDragState()
    @State private var rowFrames: [Int: CGRect] = [:]
    @State private var frozenOrder: [Workspace]?
    /// Altezza del contenuto archiviato: la sezione Archive si dimensiona su questa, cappata a metà
    /// sidebar (poi scroll interno).
    @State private var archivedHeight: CGFloat = 0

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        onNewWorkspace: @escaping () -> Void,
        onCloseWorkspace: @escaping (Workspace) -> Void,
        updateConfig: SidebarUpdateConfig? = nil
    ) {
        self.store = store
        self.settings = settings
        self.onNewWorkspace = onNewWorkspace
        self.onCloseWorkspace = onCloseWorkspace
        self.updateConfig = updateConfig
    }

    public var body: some View {
        let colors = ChromeColors(settings.theme)
        // GeometryReader per il tetto della sezione Archive (~metà sidebar): la lista principale
        // prende il resto. Split verticale, non overlay: le due aree coesistono a vista, così il
        // drag tra loro è possibile e nulla resta nascosto dietro.
        return GeometryReader { proxy in
            VStack(spacing: 0) {
                trafficLightsStrip
                workspacesHeader(colors)
                list(colors)
                if let updateConfig {
                    UpdateBanner(config: updateConfig, colors: colors)
                }
                archiveSection(colors, maxListHeight: proxy.size.height * 0.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 200)
        .background(colors.background)
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
                .font(.system(size: 11, weight: .semibold))
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

    /// Righe custom coi colori del tema: selezione/hover disegnati da noi, menu contestuale senza
    /// highlight di sistema, riordino via drag & drop. Il padding orizzontale della VStack insetta
    /// la pill di selezione dai bordi (`sm`); il contenuto della riga aggiunge `xs` così allinea
    /// con l'header (`sm + xs = md`).
    private func list(_ colors: ChromeColors) -> some View {
        // Ordine di visualizzazione (pinned in testa, poi il resto in ordine canonico). Durante un
        // drag vale lo snapshot congelato, così un evento agente (che può bumpare un workspace in
        // cima) non riordina le righe sotto il puntatore.
        let ordered = frozenOrder ?? store.orderedWorkspaces
        let space = "sidebar-reorder"
        return ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, workspace in
                    makeRow(workspace, colors: colors)
                        .reorderableRow(ReorderRowConfig(
                            id: workspace.id,
                            index: index,
                            axis: .vertical,
                            space: space,
                            count: ordered.count,
                            frames: rowFrames,
                            drag: $drag,
                            state: drag,
                            perform: { performMove(of: workspace.id, to: $0, ordered: ordered) }
                        ))
                }
            }
            .reorderableContainer(ReorderContainerConfig(
                space: space,
                axis: .vertical,
                count: ordered.count,
                frames: $rowFrames,
                insertion: drag.insertion,
                lineColor: colors.accent
            ))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .animation(.easeInOut(duration: 0.2), value: ordered.map(\.id))
            .onChange(of: drag.id) { _, id in
                frozenOrder = id == nil ? nil : store.orderedWorkspaces
            }
        }
        .scrollContentBackground(.hidden)
        .layoutPriority(1) // la lista principale tiene il flex; l'archivio prende il resto
    }

    /// Riga workspace completa (callback allo store), condivisa da lista principale e sezione
    /// Archive. I chiamanti aggiungono i modifier di riordino solo dove serve.
    private func makeRow(_ workspace: Workspace, colors: ChromeColors) -> WorkspaceRow {
        WorkspaceRow(
            workspace: workspace,
            selected: workspace.id == store.selectedWorkspaceID,
            colors: colors,
            onSelect: { store.selectWorkspace(workspace.id) },
            onTogglePin: { store.togglePin(workspace.id) },
            onRename: { store.renameWorkspace(workspace.id, to: $0) },
            // Rende il workspace di nuovo eleggibile alla nomina automatica: l'observer del
            // NamingController reagisce al ritorno di `nameOrigin` a `.default` e lo rinomina al
            // prossimo segnale. Solo store: nessun cablaggio verso il composition root.
            onRegenerateName: { store.markNameRegenerable(workspace.id) },
            onToggleUnread: { toggleUnread(workspace) },
            onToggleArchive: { store.toggleArchive(workspace.id) },
            onClose: { onCloseWorkspace(workspace) }
        )
    }

    /// Sezione Archive: header ancorato in fondo alla sidebar (sempre visibile come drop zone del
    /// drag e affordance dell'archivio, anche a vuoto), collassabile; quando espansa mostra i
    /// workspace archiviati in uno ScrollView che si adatta al contenuto fino a `maxListHeight`
    /// (~metà sidebar), poi scrolla dentro. A vuoto mostra un empty state se aperta.
    private func archiveSection(_ colors: ChromeColors, maxListHeight: CGFloat) -> some View {
        let archived = store.archivedWorkspaces
        return VStack(spacing: 0) {
            Divider()
            archiveHeader(
                colors,
                count: archived.count,
                attention: hasArchivedAttention(archived)
            )
            // Sempre nel tree, mai `if expanded` (inserire/rimuovere la view faceva un pop:
            // apriva a 1px, saltava all'altezza misurata senza animazione, e chiudeva con un
            // fade). Ad animare è solo il frame: expanded <-> 0 è una slide continua.
            // VStack, non LazyVStack: dentro uno ScrollView basso (0/1px) il lazy non
            // realizzerebbe le righe e la misura resterebbe 0 per sempre. Gli archiviati sono
            // pochi: realizzarli tutti va bene.
            // La misura passa da `onGeometryChange` sul contenuto, NON da una preference:
            // su macOS le preference non attraversano il confine dello ScrollView (bridge
            // NSScrollView), a `onPreferenceChange` fuori arrivava solo lo 0 iniziale e la
            // lista restava a 1px (la causa dell'archivio che non si apriva). La write della
            // misura è animata: copre la primissima apertura (altezza ancora ignota, 1px ->
            // misura) e i cambi di contenuto a lista aperta.
            ScrollView {
                VStack(spacing: 1) {
                    if archived.isEmpty {
                        archiveEmptyState(colors)
                    } else {
                        ForEach(archived) { workspace in
                            makeRow(workspace, colors: colors)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .onGeometryChange(
                    for: CGFloat.self,
                    of: { $0.size.height },
                    action: { height in
                        withAnimation(.easeInOut(duration: 0.2)) { archivedHeight = height }
                    }
                )
            }
            .frame(
                height: settings.archiveExpanded
                    ? min(max(archivedHeight, 1), maxListHeight)
                    : 0
            )
            .scrollContentBackground(.hidden)
        }
    }

    /// Empty state dell'archivio aperto e vuoto: una riga discreta, non un box vistoso.
    private func archiveEmptyState(_ colors: ChromeColors) -> some View {
        Text("No archived workspaces")
            .font(Theme.Typography.subtitle)
            .foregroundStyle(colors.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Theme.Spacing.sm)
    }

    /// Header cliccabile della sezione Archive: chevron, conteggio, e un pallino discreto se un
    /// archiviato ha attenzione fresca (così l'archivio non è un buco nero, senza galleggiare).
    private func archiveHeader(_ colors: ChromeColors, count: Int, attention: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { settings.toggleArchiveExpanded() }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                // Un solo glifo ruotato, non uno swap chevron.right/down: il cambio di simbolo
                // non interpola (crossfade sfasato rispetto alla slide), la rotazione anima in
                // sync con l'altezza della lista nella stessa transaction.
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(colors.secondary)
                    .rotationEffect(.degrees(settings.archiveExpanded ? 90 : 0))
                    .frame(width: 10)
                Image(systemName: "archivebox")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.secondary)
                Text("Archive")
                    .font(Theme.Typography.item)
                    .foregroundStyle(colors.foreground)
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.Typography.subtitle)
                        .foregroundStyle(colors.secondary)
                }
                Spacer()
                if attention {
                    Circle().fill(colors.accent).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(settings.archiveExpanded ? "Collapse archive" : "Expand archive")
    }

    private func hasArchivedAttention(_ archived: [Workspace]) -> Bool {
        archived.contains { $0.needsAttention }
    }

    /// Toggle manuale del marker di attenzione dal menu contestuale: agisce sulla tab selezionata
    /// del workspace (il marker vive per-tab). Estratto dal `ForEach` per non appesantire
    /// l'inferenza di tipo della riga.
    private func toggleUnread(_ workspace: Workspace) {
        guard let tabID = workspace.selectedTab?.id else { return }
        store.toggleUnread(tabID)
    }

    /// Esegue lo spostamento deciso dal resolver puro (`SidebarDrop`): eventuale pin/unpin per
    /// attraversamento del blocco pinned + inserimento canonico ancorato a un vicino. Il reset
    /// dello stato di drag lo fa la resetTransaction del @GestureState.
    private func performMove(of dragID: UUID, to insertion: Int, ordered: [Workspace]) {
        let rows = ordered.map {
            SidebarDrop.Row(id: $0.id, pinned: $0.pinned)
        }
        guard let drop = SidebarDrop.resolve(rows: rows, dragID: dragID, insertion: insertion)
        else { return }
        if drop.pinned != nil { store.togglePin(dragID) }
        switch drop.move {
        case let .before(target): store.moveWorkspace(dragID, before: target)
        case let .after(target): store.moveWorkspace(dragID, after: target)
        case nil: break
        }
    }
}
