import Foundation

/// Un elemento di primo livello della sidebar: un workspace libero oppure un gruppo con i suoi
/// membri. È la proiezione che la sidebar disegna e su cui si muove la navigazione; l'ordine vero
/// resta l'array canonico dello store (`workspaces`), qui solo raggruppato e proiettato.
public enum SidebarItem: Identifiable {
    case workspace(Workspace)
    case group(WorkspaceGroup, members: [Workspace])

    public var id: UUID {
        switch self {
        case let .workspace(workspace): workspace.id
        case let .group(group, _): group.id
        }
    }

    /// In testa alla sidebar: un workspace pinned o un gruppo pinned (che sale col suo blocco).
    public var pinned: Bool {
        switch self {
        case let .workspace(workspace): workspace.pinned
        case let .group(group, _): group.pinned
        }
    }

    /// I workspace dell'elemento in ordine visivo: uno solo, o i membri del gruppo.
    public var workspaces: [Workspace] {
        switch self {
        case let .workspace(workspace): [workspace]
        case let .group(_, members): members
        }
    }

    /// I workspace **raggiungibili a vista**: i membri di un gruppo collassato non si vedono,
    /// quindi non entrano nella numerazione `Cmd+1..9` né nel menu Go (una scorciatoia che
    /// seleziona una riga invisibile non è una scorciatoia).
    public var visibleWorkspaces: [Workspace] {
        switch self {
        case let .workspace(workspace): [workspace]
        case let .group(group, members): group.collapsed ? [] : members
        }
    }
}

public extension WorkspaceStore {
    /// Gli elementi di primo livello della sidebar di una finestra: workspace liberi e gruppi,
    /// nello
    /// stesso criterio di `orderedWorkspaces` (archiviati fuori, pinned in testa).
    ///
    /// La posizione di un gruppo è quella del suo **primo membro** nell'ordine canonico, e i membri
    /// vengono raccolti tutti lì: la contiguità dei membri nell'array è una comodità che le
    /// operazioni mantengono, non un invariante da cui dipende la correttezza (un file toccato a
    /// mano che sparpaglia i membri produce comunque una card sola, non righe orfane). Un
    /// `groupID` che punta a un gruppo inesistente degrada a workspace libero.
    func sidebarItems(in windowID: UUID) -> [SidebarItem] {
        let visible = workspaces.filter { $0.windowID == windowID && !$0.archived }
        var items: [SidebarItem] = []
        var seenGroups: Set<UUID> = []
        for workspace in visible {
            guard let groupID = workspace.groupID,
                  let group = groups.first(where: { $0.id == groupID })
            else {
                items.append(.workspace(workspace))
                continue
            }
            guard seenGroups.insert(groupID).inserted else { continue }
            items.append(.group(group, members: visible.filter { $0.groupID == groupID }))
        }
        return items.filter(\.pinned) + items.filter { !$0.pinned }
    }

    /// Gli elementi della sidebar della finestra key.
    var sidebarItems: [SidebarItem] {
        sidebarItems(in: keyWindowID)
    }

    /// I workspace raggiungibili dalle scorciatoie numeriche e dal menu Go: ordine visivo, membri
    /// di gruppi collassati esclusi (vedi `SidebarItem.visibleWorkspaces`).
    func navigableWorkspaces(in windowID: UUID) -> [Workspace] {
        sidebarItems(in: windowID).flatMap(\.visibleWorkspaces)
    }

    var navigableWorkspaces: [Workspace] {
        navigableWorkspaces(in: keyWindowID)
    }
}
