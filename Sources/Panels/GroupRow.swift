import SwiftUI
import WorkspaceModel

/// Azioni di un gruppo, iniettate dalla sidebar: la riga non conosce lo store.
struct GroupActions {
    let onToggleCollapse: () -> Void
    let onRename: (String) -> Void
    let onSetColor: (Int) -> Void
    let onTogglePin: () -> Void
    let onUngroup: () -> Void
}

/// Header di una card di gruppo: una riga sola col titolo, il chevron di collasso e lo spazio per
/// il menu della card. A card chiusa è alta come una riga normale e porta i conteggi al posto dei
/// membri: quelli **da vedere** nel colore del gruppo (è il dato azionabile: senza, un gruppo
/// chiuso è un buco nero) e il totale in grigio.
struct GroupHeaderRow: View {
    let group: WorkspaceGroup
    let members: [Workspace]
    let colors: ChromeColors
    let actions: GroupActions

    @State private var hovered = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    private var tint: Color {
        colors.group(group.safeColorIndex)
    }

    private var attentionCount: Int {
        members.count { $0.needsAttention }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            // Un solo glifo ruotato, non uno swap di simboli: la rotazione interpola in sync con
            // l'apertura della card (stesso criterio della sezione Archive).
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
                .rotationEffect(.degrees(group.collapsed ? 0 : 90))
                .frame(width: 10)
            if editing {
                nameField
            } else {
                Text(group.name)
                    .font(Theme.Typography.sectionHeader)
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)
            }
            if group.pinned {
                Image(systemName: "pin.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(tint)
            }
            Spacer(minLength: Theme.Spacing.xs)
            if !editing {
                counters
                menuButton
            }
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(hovered ? tint.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: actions.onToggleCollapse)
        .onHover { hovered = $0 }
        .contextMenu { menuContent }
    }

    /// Un numero alla volta, mai due affiancati ("2 2" non si legge): a card chiusa con qualcosa
    /// da vedere conta **quelli**, nel colore del gruppo (è il dato azionabile: senza, una card
    /// chiusa è un buco nero); altrimenti il totale dei membri, in grigio.
    @ViewBuilder private var counters: some View {
        if group.collapsed, attentionCount > 0 {
            Text("\(attentionCount)")
                .font(Theme.Typography.caption)
                .foregroundStyle(tint)
        } else {
            Text("\(members.count)")
                .font(Theme.Typography.caption)
                .foregroundStyle(colors.secondary)
        }
    }

    /// Lo spazio per il menu della card chiesto dal design: compare su hover, come la x delle
    /// righe, per non fare rumore a riposo.
    @ViewBuilder private var menuButton: some View {
        if hovered {
            Menu {
                menuContent
            } label: {
                Image(systemName: "ellipsis")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(colors.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 16)
        }
    }

    @ViewBuilder private var menuContent: some View {
        Button("Rename Group", action: beginRename)
        Button(group.collapsed ? "Expand" : "Collapse", action: actions.onToggleCollapse)
        Button(group.pinned ? "Unpin Group" : "Pin Group", action: actions.onTogglePin)
        Menu("Color") {
            ForEach(WorkspaceGroup.colorIndices, id: \.self) { index in
                Button(GroupHeaderRow.colorName(index)) { actions.onSetColor(index) }
            }
        }
        Button("Ungroup", action: actions.onUngroup)
    }

    /// Nome del colore ANSI: la palette è quella del tema, quindi l'etichetta descrive lo slot
    /// (rosso, verde, ...), non una tinta esatta - che cambia col tema.
    static func colorName(_ index: Int) -> String {
        switch index {
        case 1: "Red"
        case 2: "Green"
        case 3: "Yellow"
        case 4: "Blue"
        case 5: "Magenta"
        default: "Cyan"
        }
    }

    private var nameField: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(colors.foreground)
            .focused($nameFocused)
            .onSubmit(commit)
            .onExitCommand { editing = false }
            .onChange(of: nameFocused) { _, focused in
                if !focused { commit() }
            }
            .onAppear { DispatchQueue.main.async { nameFocused = true } }
    }

    private func beginRename() {
        draft = group.name
        editing = true
    }

    private func commit() {
        guard editing else { return }
        editing = false
        actions.onRename(draft)
    }
}

/// La card colorata attorno a un gruppo: fondo tenue nella tinta del gruppo, bordo sottile e
/// rientro dei membri. Contenitore puro (prende il contenuto dal chiamante) così la sidebar può
/// montarci dentro le righe vere, che restano misurate nel coordinate space condiviso del drag.
struct GroupCard<Content: View>: View {
    let tint: Color
    let colors: ChromeColors
    /// Card chiusa: senza membri non c'è la riga di coda, quindi il padding inferiore lo mette il
    /// contenitore - altrimenti l'header resterebbe appoggiato al bordo basso.
    let collapsed: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 1) {
            content
        }
        // Padding leggero e uniforme sui quattro lati. Da aperta quello in fondo lo dà la riga di
        // coda (`groupTail`, vedi SidebarLayout), che è padding *e* slot di rilascio: sommarci
        // anche quello del contenitore darebbe il vuoto sproporzionato sotto l'ultimo membro.
        .padding(.horizontal, Theme.Spacing.xs)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, collapsed ? Theme.Spacing.xs : 0)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                )
        )
    }
}
