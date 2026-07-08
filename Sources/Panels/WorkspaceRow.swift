import SwiftUI
import WorkspaceModel

/// Riga workspace con selezione/hover dal tema. View separata per lo stato locale (hover +
/// editing): su hover il badge di severità lascia il posto alla x di chiusura; il rename dal
/// menu contestuale scambia il nome con un `TextField` inline.
struct WorkspaceRow: View {
    let workspace: Workspace
    let selected: Bool
    let colors: ChromeColors
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onRename: (String) -> Void
    let onRegenerateName: () -> Void
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
            if !workspace.archived {
                Button(workspace.pinned ? "Unpin" : "Pin", action: onTogglePin)
            }
            // Toggle del marker sulla tab selezionata: riaccende o spegne il segnale di attenzione
            // a mano (metafora unread). Il label riflette lo stato corrente della tab selezionata.
            Button(isUnseen ? "Mark as Read" : "Mark as Unread", action: onToggleUnread)
            Button(workspace.archived ? "Unarchive" : "Archive", action: onToggleArchive)
            Button("Close", role: .destructive, action: onClose)
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
