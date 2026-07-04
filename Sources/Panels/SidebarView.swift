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

    // Stato del riordino via drag & drop (vedi Reorderable): quale workspace è in volo, la sua
    // traslazione corrente, i frame delle righe (per l'indicatore) e la posizione di inserimento.
    @State private var draggingWorkspaceID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var rowFrames: [Int: CGRect] = [:]
    @State private var dropInsertion: Int?

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
        return VStack(spacing: 0) {
            trafficLightsStrip
            workspacesHeader(colors)
            list(colors)
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
        // Ordine di visualizzazione (pinned, poi con attenzione, poi resto); l'ordine canonico
        // dello store resta invariato. `ordered` guida sia le righe sia l'animazione di riordino.
        let ordered = store.orderedWorkspaces
        let space = "sidebar-reorder"
        return ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, workspace in
                    WorkspaceRow(
                        workspace: workspace,
                        selected: workspace.id == store.selectedWorkspaceID,
                        colors: colors,
                        onSelect: { store.selectWorkspace(workspace.id) },
                        onTogglePin: { store.togglePin(workspace.id) },
                        onRename: { store.renameWorkspace(workspace.id, to: $0) },
                        onClose: { onCloseWorkspace(workspace) }
                    )
                    .reorderFrame(index, in: space)
                    .reorderableRow(ReorderRowConfig(
                        id: workspace.id,
                        axis: .vertical,
                        space: space,
                        count: ordered.count,
                        frames: rowFrames,
                        dragging: $draggingWorkspaceID,
                        translation: $dragTranslation,
                        insertion: $dropInsertion,
                        clamp: { clampToSegment($0, ordered: ordered) },
                        perform: { performMove(to: $0, ordered: ordered) }
                    ))
                }
            }
            .reorderableContainer(ReorderContainerConfig(
                space: space,
                axis: .vertical,
                count: ordered.count,
                frames: $rowFrames,
                insertion: dropInsertion,
                lineColor: colors.accent
            ))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .animation(.easeInOut(duration: 0.2), value: ordered.map(\.id))
        }
        .scrollContentBackground(.hidden)
    }

    /// Vincola l'inserimento al segmento di float del workspace trascinato: la linea si muove solo
    /// tra le righe dello stesso gruppo (pinned/attenzione/resto), perché il float non lascia
    /// attraversare i segmenti. Così l'indicatore non promette una posizione che il float annulla.
    private func clampToSegment(_ raw: Int, ordered: [Workspace]) -> Int {
        guard let dragID = draggingWorkspaceID,
              let dragIndex = ordered.firstIndex(where: { $0.id == dragID }) else { return raw }
        let segment = store.segmentIndex(for: ordered[dragIndex])
        guard let lo = ordered.firstIndex(where: { store.segmentIndex(for: $0) == segment }),
              let hi = ordered.lastIndex(where: { store.segmentIndex(for: $0) == segment })
        else { return raw }
        return min(max(raw, lo), hi + 1)
    }

    /// Esegue lo spostamento: inserisce il workspace trascinato prima della riga `insertion`
    /// (o in fondo). Il target è preso dall'ordine visivo; entro lo stesso segmento coincide con
    /// l'ordine canonico su cui opera lo store. Il reset di `draggingWorkspaceID` lo fa il
    /// modifier.
    private func performMove(to insertion: Int, ordered: [Workspace]) {
        guard let dragID = draggingWorkspaceID,
              let dragIndex = ordered.firstIndex(where: { $0.id == dragID }) else { return }
        // Rilascio in fondo al proprio segmento di float (non l'ultimo): `ordered[insertion]` è il
        // primo del segmento visivo successivo, che in ordine canonico non è contiguo, quindi
        // `before` sarebbe un no-op. Inserisco invece dopo l'ultimo del segmento.
        let segment = store.segmentIndex(for: ordered[dragIndex])
        let segmentEnd = ordered.lastIndex { store.segmentIndex(for: $0) == segment }
        if let segmentEnd, insertion == segmentEnd + 1, insertion < ordered.count {
            store.moveWorkspace(dragID, after: ordered[segmentEnd].id)
            return
        }
        let targetID = insertion < ordered.count ? ordered[insertion].id : nil
        store.moveWorkspace(dragID, before: targetID)
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
            Button(workspace.pinned ? "Unpin" : "Pin", action: onTogglePin)
            Button("Close", role: .destructive, action: onClose)
        }
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
