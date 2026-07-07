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
        onCloseWorkspace: @escaping (Workspace) -> Void
    ) {
        self.store = store
        self.settings = settings
        self.onNewWorkspace = onNewWorkspace
        self.onCloseWorkspace = onCloseWorkspace
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
            onToggleUnread: { toggleUnread(workspace) },
            onToggleArchive: { store.toggleArchive(workspace.id) },
            onClose: { onCloseWorkspace(workspace) }
        )
    }

    /// Sezione Archive: header ancorato in fondo alla sidebar (sempre visibile come drop zone del
    /// drag), collassabile; quando espansa mostra i workspace archiviati in uno ScrollView che si
    /// adatta al contenuto fino a `maxListHeight` (~metà sidebar), poi scrolla dentro. Assente se
    /// non ci sono archiviati.
    @ViewBuilder
    private func archiveSection(_ colors: ChromeColors, maxListHeight: CGFloat) -> some View {
        let archived = store.archivedWorkspaces
        if !archived.isEmpty {
            VStack(spacing: 0) {
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
                        ForEach(archived) { workspace in
                            makeRow(workspace, colors: colors)
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
                Text("\(count)")
                    .font(Theme.Typography.subtitle)
                    .foregroundStyle(colors.secondary)
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

/// Riga workspace con selezione/hover dal tema. View separata per lo stato locale (hover +
/// editing): su hover il badge di severità lascia il posto alla x di chiusura; il rename dal
/// menu contestuale scambia il nome con un `TextField` inline.
private struct WorkspaceRow: View {
    let workspace: Workspace
    let selected: Bool
    let colors: ChromeColors
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onRename: (String) -> Void
    let onToggleUnread: () -> Void
    let onToggleArchive: () -> Void
    let onClose: () -> Void

    @State private var hovered = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: workspace.pinned ? "pin.fill" : "folder")
                .foregroundStyle(workspace.pinned ? colors.accent : colors.secondary)
                .font(.system(size: 12))
                // Larghezza fissa: i simboli SF hanno larghezze intrinseche diverse (pin più
                // stretto di folder), altrimenti il testo scatta orizzontalmente al pin/unpin.
                .frame(width: 16)
                .padding(.trailing, Theme.Spacing.sm)
            VStack(alignment: .leading, spacing: 1) {
                if editing {
                    nameField
                } else {
                    Text(workspace.name)
                        .font(Theme.Typography.item)
                        .foregroundStyle(colors.foreground)
                        .lineLimit(1)
                }
                // Cosa succede nella tab selezionata: nome chat Claude (titolo OSC) o cwd. Resta
                // visibile anche in rename, così la riga non cambia altezza.
                if let subtitle = WindowTitle.workspaceSubtitle(workspace) {
                    Text(subtitle)
                        .font(Theme.Typography.subtitle)
                        .foregroundStyle(colors.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Slot trailing riservato (pattern A): badge e x occupano lo stesso spazio, così su
            // hover il sottotitolo non ri-tronca. `minWidth` (non width fissa) così i badge larghi
            // (col contatore) non si clippano. In editing lo slot sparisce: il campo nome prende
            // tutta la riga.
            if !editing {
                trailing
                    .frame(minWidth: 14, alignment: .trailing)
                    .padding(.leading, Theme.Spacing.xs)
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(selected ? colors.selection : hovered ? colors.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Rename", action: beginRename)
            // Pin e Archive sono opposti: un archiviato non si pinna (lo mostro solo se in lista).
            if !workspace.archived {
                Button(workspace.pinned ? "Unpin" : "Pin", action: onTogglePin)
            }
            // Toggle del marker sulla tab selezionata: riaccende o spegne il segnale di attenzione
            // a mano (metafora unread). Il label riflette lo stato corrente della tab selezionata.
            Button(hasAttention ? "Mark as Read" : "Mark as Unread", action: onToggleUnread)
            Button(workspace.archived ? "Unarchive" : "Archive", action: onToggleArchive)
            Button("Close", role: .destructive, action: onClose)
        }
    }

    /// La tab selezionata del workspace ha un marker acceso (unseen o pending): guida il label del
    /// toggle unread nel menu contestuale.
    private var hasAttention: Bool {
        (workspace.selectedTab?.attention ?? .none) != .none
    }

    /// Campo di rinomina inline: commit su Invio o perdita focus, Esc annulla.
    private var nameField: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(Theme.Typography.item)
            .foregroundStyle(colors.foreground)
            .focused($nameFocused)
            .onSubmit(commit)
            .onExitCommand(perform: cancel)
            .onChange(of: nameFocused) { _, focused in
                if !focused { commit() }
            }
            .onAppear { DispatchQueue.main.async { nameFocused = true } }
    }

    /// Su hover mostra la x di chiusura; a riposo il badge di severità aggregato.
    @ViewBuilder private var trailing: some View {
        if hovered {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain) // niente padding/bezel del bottone: glyph a filo come il badge
            .foregroundStyle(colors.secondary)
            .help("Close workspace")
        } else {
            WorkspaceBadge(workspace: workspace, colors: colors)
        }
    }

    private func beginRename() {
        draft = workspace.name
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
