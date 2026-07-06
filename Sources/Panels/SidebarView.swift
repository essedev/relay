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
        // dello store resta invariato. Durante un drag vale lo snapshot congelato, così un evento
        // agente non ri-partiziona le righe sotto il puntatore.
        let ordered = frozenOrder ?? store.orderedWorkspaces
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
    }

    /// Esegue lo spostamento deciso dal resolver puro (`SidebarDrop`): eventuale pin/unpin per
    /// attraversamento del blocco pinned + inserimento canonico ancorato a un vicino. Il reset
    /// dello stato di drag lo fa la resetTransaction del @GestureState.
    private func performMove(of dragID: UUID, to insertion: Int, ordered: [Workspace]) {
        let rows = ordered.map {
            SidebarDrop.Row(id: $0.id, pinned: $0.pinned, attention: $0.needsAttention)
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
