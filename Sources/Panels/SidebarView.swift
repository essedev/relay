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
    /// Doppio click sull'header (riga dei semafori) = comportamento title bar di macOS (zoom).
    let onTitleBarDoubleClick: () -> Void

    public init(
        store: WorkspaceStore,
        settings: AppSettings,
        onNewWorkspace: @escaping () -> Void,
        onCloseWorkspace: @escaping (Workspace) -> Void,
        onTitleBarDoubleClick: @escaping () -> Void = {}
    ) {
        self.store = store
        self.settings = settings
        self.onNewWorkspace = onNewWorkspace
        self.onCloseWorkspace = onCloseWorkspace
        self.onTitleBarDoubleClick = onTitleBarDoubleClick
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
        Color.clear
            .frame(height: Theme.Metrics.titleBarHeight)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onTitleBarDoubleClick() }
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
        return ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(ordered) { workspace in
                    WorkspaceRow(
                        workspace: workspace,
                        selected: workspace.id == store.selectedWorkspaceID,
                        colors: colors,
                        onSelect: { store.selectWorkspace(workspace.id) },
                        onTogglePin: { store.togglePin(workspace.id) },
                        onRename: { store.renameWorkspace(workspace.id, to: $0) },
                        onClose: { onCloseWorkspace(workspace) }
                    )
                    .draggable(workspace.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        guard let first = items.first, let dragged = UUID(uuidString: first) else {
                            return false
                        }
                        store.moveWorkspace(dragged, onto: workspace.id)
                        return true
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .animation(.easeInOut(duration: 0.2), value: ordered.map(\.id))
        }
        .scrollContentBackground(.hidden)
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
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: workspace.pinned ? "pin.fill" : "folder")
                .foregroundStyle(workspace.pinned ? colors.accent : colors.secondary)
                .font(.system(size: 12))
                // Larghezza fissa: i simboli SF hanno larghezze intrinseche diverse (pin più
                // stretto di folder), altrimenti il testo scatta orizzontalmente al pin/unpin.
                .frame(width: 16)
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
            Spacer(minLength: Theme.Spacing.xs)
            if !editing { trailing }
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
            .buttonStyle(.borderless)
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
