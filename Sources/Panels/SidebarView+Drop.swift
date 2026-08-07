import SwiftUI
import WorkspaceModel

// Sezione Archive, riga in volo e applicazione del drop. Estratti da `SidebarView` per il budget
// di dimensione dei file (vedi CONVENTIONS).

extension SidebarView {
    /// Sezione Archive: header ancorato in fondo alla sidebar (sempre visibile come drop zone del
    /// drag e affordance dell'archivio, anche a vuoto), collassabile; quando espansa mostra i
    /// workspace archiviati in uno ScrollView che si adatta al contenuto fino a `maxListHeight`
    /// (~metà sidebar), poi scrolla dentro. A vuoto mostra un empty state se aperta.
    func archiveSection(
        _ archived: [Workspace],
        plan: SidebarLayout.Plan,
        colors: ChromeColors,
        maxListHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            Divider()
            archiveHeader(colors, count: archived.count, attention: hasArchivedAttention(archived))
                .sidebarReorderSlot(
                    index: plan.index(of: .archiveHeader),
                    space: SidebarView.space,
                    onFrame: { frames[$0] = $1 }
                )
            // Sempre nel tree, mai `if expanded` (inserire/rimuovere la view faceva un pop:
            // apriva a 1px, saltava all'altezza misurata senza animazione, e chiudeva con un
            // fade). Ad animare è solo il frame: expanded <-> 0 è una slide continua.
            // VStack, non LazyVStack: dentro uno ScrollView basso (0/1px) il lazy non
            // realizzerebbe le righe e la misura resterebbe 0 per sempre.
            // La misura passa da `onGeometryChange`, NON da una preference: su macOS le
            // preference non attraversano il confine dello ScrollView (bridge NSScrollView), a
            // `onPreferenceChange` fuori arrivava solo lo 0 iniziale e la lista restava a 1px
            // (la causa dell'archivio che non si apriva).
            ScrollView {
                VStack(spacing: 1) {
                    if archived.isEmpty {
                        archiveEmptyState(colors)
                    } else {
                        ForEach(archived) { workspace in
                            draggable(
                                .workspace(workspace.id),
                                plan: plan,
                                row: .archived(workspace.id),
                                viewport: .archive
                            ) {
                                makeRow(workspace, colors: colors)
                            }
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
            .onGeometryChange(
                for: CGRect.self,
                of: { $0.frame(in: .named(SidebarView.space)) },
                action: { archiveViewport = $0 }
            )
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
    private func archiveHeader(
        _ colors: ChromeColors, count: Int, attention: Bool
    ) -> some View {
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
                    .font(Theme.Typography.rowIcon)
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
                    StatusDot(color: colors.accent, size: Theme.Metrics.presenceDot)
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

    // MARK: - Riga in volo

    /// La copia della riga trascinata, disegnata **sopra la sidebar** e non dentro la sua
    /// ScrollView: seguendo il puntatore esce dal contenitore d'origine (dalla lista all'archivio e
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
    /// gruppo, archivio) e poi il riordino posizionale. Il resolver è puro (`SidebarDrop`), qui c'è
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
            store.setArchived(id, false)
            store.setPinned(id, pinned)
        case let .group(groupID):
            store.setArchived(id, false)
            store.assignGroup(id, to: groupID)
        case .archive:
            store.assignGroup(id, to: nil)
            store.setArchived(id, true)
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
