import SwiftUI
import WorkspaceModel

/// Riga workspace con selezione/hover dal tema. View separata per lo stato locale (hover +
/// editing): su hover il badge di severità lascia il posto alla x di chiusura; il rename dal
/// menu contestuale scambia il nome con un `TextField` inline.
/// Voci di gruppo del menu contestuale di una riga. `nil` sulle righe che non possono stare in una
/// card (gli archiviati).
struct WorkspaceGroupMenu {
    let inGroup: Bool
    /// Gruppi in cui si può entrare (esclusa la card in cui si è già), nome per la voce di menu.
    let available: [(id: UUID, name: String)]
    let onNewGroup: () -> Void
    let onAddToGroup: (UUID) -> Void
    let onRemoveFromGroup: () -> Void
}

struct WorkspaceRow: View {
    let workspace: Workspace
    let selected: Bool
    /// Una tab trascinata da una strip è sospesa su questa riga: rilasciarla la sposta qui.
    var dropTargeted: Bool = false
    let colors: ChromeColors
    let groupMenu: WorkspaceGroupMenu?
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onRename: (String) -> Void
    let onRegenerateName: () -> Void
    let onToggleUnread: () -> Void
    let onToggleArchive: () -> Void
    /// Sposta il workspace in una finestra nuova. `nil` = non mostrare la voce (è l'unico della sua
    /// finestra: la lascerebbe vuota, e lo store lo rifiuterebbe).
    let onMoveToNewWindow: (() -> Void)?
    let onClose: () -> Void

    @State private var hovered = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: workspace.pinned ? "pin.fill" : "folder")
                .foregroundStyle(workspace.pinned ? colors.accent : colors.secondary)
                .font(Theme.Typography.rowIcon)
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
        // Bersaglio del drop di una tab: contorno, non riempimento, così resta distinguibile dalla
        // riga selezionata (che è già piena) mentre trascini.
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(colors.accent, lineWidth: dropTargeted ? 2 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Rename", action: beginRename)
            // Ripete la nomina automatica: rende il workspace di nuovo eleggibile (torna
            // `.default`,
            // il NamingController lo ripesca dall'observer). Utile su un nome generato non
            // azzeccato
            // o per rinominare un nome scelto a mano tramite AI.
            Button("Regenerate name", action: onRegenerateName)
            // Pin e Archive sono opposti: un archiviato non si pinna (lo mostro solo se in lista).
            // Dentro una card nemmeno: lì a salire in testa è il gruppo intero.
            if !workspace.archived, workspace.groupID == nil {
                Button(workspace.pinned ? "Unpin" : "Pin", action: onTogglePin)
            }
            groupSection
            // Toggle del marker sulla tab selezionata: riaccende o spegne il segnale di attenzione
            // a mano (metafora unread). Il label riflette lo stato corrente della tab selezionata.
            Button(isUnseen ? "Mark as Read" : "Mark as Unread", action: onToggleUnread)
            Button(workspace.archived ? "Unarchive" : "Archive", action: onToggleArchive)
            if let onMoveToNewWindow {
                // Ci va con le sue tab e le sue sessioni vive: le finestre partizionano i
                // workspace, non li duplicano.
                Button("Move to New Window", action: onMoveToNewWindow)
            }
            Button("Close", role: .destructive, action: onClose)
        }
    }

    /// Voci di raggruppamento: creare una card attorno a questa riga, spostarla in una esistente,
    /// tirarla fuori. Il drag fa lo stesso lavoro, ma il menu resta la via precisa (e l'unica su
    /// una sidebar lunga, dove la card di destinazione può essere fuori vista).
    @ViewBuilder private var groupSection: some View {
        if let groupMenu {
            Divider()
            Button("New Group with This", action: groupMenu.onNewGroup)
            if !groupMenu.available.isEmpty {
                Menu("Move to Group") {
                    ForEach(groupMenu.available, id: \.id) { group in
                        Button(group.name) { groupMenu.onAddToGroup(group.id) }
                    }
                }
            }
            if groupMenu.inGroup {
                Button("Remove from Group", action: groupMenu.onRemoveFromGroup)
            }
            Divider()
        }
    }

    /// La tab selezionata del workspace è in `unseen` (segnale forte, non visto): guida il label
    /// del toggle unread nel menu contestuale. Solo `unseen` è "unread" -> "Mark as Read";
    /// `pending` è già visto (quieto) -> "Mark as Unread" (ri-alza a forte).
    private var isUnseen: Bool {
        (workspace.selectedTab?.attention ?? .none) == .unseen
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
            // glyph a filo come il badge che rimpiazza a riposo (default size 9)
            CloseButton(color: colors.secondary, help: "Close workspace", action: onClose)
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
