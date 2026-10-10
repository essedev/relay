import SwiftUI
import WorkspaceModel

// Riga in volo e applicazione del drop. Estratti da `SidebarView` per il budget di dimensione dei
// file (vedi CONVENTIONS).

extension SidebarView {
    // MARK: - Riga in volo

    /// La copia della riga trascinata, disegnata **sopra la sidebar** e non dentro la sua
    /// ScrollView: seguendo il puntatore esce dal contenitore d'origine (da una card alla lista e
    /// viceversa), e la riga vera clippata al bordo sparirebbe a metà gesto. L'originale resta al
    /// suo posto, sbiadito.
    @ViewBuilder
    func flyingRow(colors: ChromeColors) -> some View {
        if let dragged = drag.dragged, let frame = frames[drag.index] {
            flyingContent(dragged, colors: colors)
                .frame(width: frame.width, height: frame.height)
                .opacity(0.9)
                .shadow(radius: 6, y: 2)
                .offset(x: frame.minX, y: frame.minY + drag.translation)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func flyingContent(
        _ dragged: SidebarDrop.Dragged, colors: ChromeColors
    ) -> some View {
        switch dragged {
        case let .workspace(id):
            if let workspace = store.workspaces.first(where: { $0.id == id }) {
                makeRow(workspace, colors: colors)
                    .background(colors.background)
            }
        case let .group(id):
            if let group = store.group(id) {
                GroupHeaderRow(
                    group: group,
                    members: store.members(of: id),
                    colors: colors,
                    actions: GroupActions(
                        onToggleCollapse: {}, onRename: { _ in },
                        onSetColor: { _ in }, onTogglePin: {}, onUngroup: {}
                    )
                )
                .background(colors.group(group.safeColorIndex).opacity(0.16))
            }
        }
    }

    /// Rientro della linea di inserimento: dentro una card si allinea ai membri, così l'anteprima
    /// dice anche *in che contenitore* stai per rilasciare, non solo a che altezza.
    func insertionIndent(plan: SidebarLayout.Plan) -> CGFloat {
        guard let insertion = drag.insertion, drag.dragged != nil,
              let slot = plan.slots[safe: insertion], case .group = slot
        else { return Theme.Spacing.sm }
        return Theme.Spacing.sm + Theme.Spacing.md
    }

    // MARK: - Drop

    /// Applica il rilascio: cambi di campo dedotti dal **contenitore** di destinazione (pin,
    /// gruppo) e poi il riordino posizionale. Il resolver è puro (`SidebarDrop`), qui c'è
    /// solo la traduzione in comandi dello store.
    func performDrop(_ dragged: SidebarDrop.Dragged, at insertion: Int, plan: SidebarLayout.Plan) {
        let items = (frozenItems ?? store.sidebarItems(in: windowID)).map(descriptor)
        guard let drop = SidebarDrop.resolve(
            plan: plan, items: items, dragged: dragged, insertion: insertion
        ) else { return }
        switch dragged {
        case let .workspace(id): applyWorkspaceDrop(id, drop)
        case let .group(id): applyGroupDrop(id, drop)
        }
    }

    private func applyWorkspaceDrop(_ id: UUID, _ drop: SidebarDrop.Resolution) {
        switch drop.container {
        case let .root(pinned):
            store.assignGroup(id, to: nil)
            store.setPinned(id, pinned)
        case let .group(groupID):
            store.assignGroup(id, to: groupID)
        }
        apply(drop.move, to: id)
    }

    /// Una card si muove solo nella lista (il resolver le nega gli altri slot): resta il pin del
    /// blocco e lo spostamento di tutti i membri.
    private func applyGroupDrop(_ id: UUID, _ drop: SidebarDrop.Resolution) {
        if case let .root(pinned) = drop.container {
            store.setGroupPinned(id, pinned)
        }
        switch drop.move {
        case let .before(target): store.moveGroup(id, before: target)
        case let .after(target): store.moveGroup(id, after: target)
        case nil: break
        }
    }

    private func apply(_ move: SidebarDrop.Move?, to id: UUID) {
        switch move {
        case let .before(target): store.moveWorkspace(id, before: target)
        case let .after(target): store.moveWorkspace(id, after: target)
        case nil: break
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
