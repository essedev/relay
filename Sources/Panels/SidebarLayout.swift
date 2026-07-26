import Foundation

/// La sidebar srotolata in **righe** e **slot**, indipendente da SwiftUI: è ciò che il drag & drop
/// misura e ciò su cui il resolver decide. Puro e testato.
///
/// Righe e slot sono due cose diverse e serve tenerle distinte: la riga è ciò che si vede e si
/// trascina, lo **slot** è lo spazio *fra* due righe, cioè un possibile punto di rilascio. Ci sono
/// `rows.count + 1` slot, e ognuno porta scritto **in quale contenitore** finisce ciò che ci
/// rilasci (lista, card di un gruppo, archivio).
///
/// Il contenitore per slot è deciso qui, alla costruzione, e non da euristiche sui vicini al
/// momento del drop: il confine fra "in fondo alla card" e "sotto la card" è lo stesso pixel per
/// due significati diversi, e nessuna regola sui vicini lo può sciogliere. Lo sciogliamo dando al
/// gruppo una riga di coda (`groupTail`, il padding inferiore della card): lo slot *prima* di lei
/// è dentro il gruppo, quello *dopo* è nella lista. Un solo significato per slot.
enum SidebarLayout {
    /// Dove finisce un workspace rilasciato in uno slot.
    enum Container: Equatable {
        /// Lista principale. `pinned` = blocco in testa (stessa semantica di prima dei gruppi:
        /// attraversare il blocco pinna o spinna).
        case root(pinned: Bool)
        case group(UUID)
        case archive
    }

    /// Una riga disegnata in sidebar. `groupTail` non ha contenuto: è il padding in fondo alla
    /// card, che esiste come riga solo per dare uno slot proprio al "sotto la card".
    enum Row: Equatable {
        case workspace(UUID)
        case groupHeader(UUID)
        case member(UUID, group: UUID)
        case groupTail(UUID)
        case archiveHeader
        case archived(UUID)
    }

    /// Natura di un elemento di primo livello: riga libera o card coi suoi membri.
    enum ItemKind: Equatable {
        case workspace
        case group(members: [UUID], collapsed: Bool)
    }

    /// Elemento di primo livello in ingresso: lo specchio puro di `WorkspaceModel.SidebarItem`,
    /// senza dipendere dai suoi tipi osservabili (così i test costruiscono casi a mano).
    struct Item: Equatable {
        let id: UUID
        let kind: ItemKind
        let pinned: Bool

        init(id: UUID, kind: ItemKind, pinned: Bool) {
            self.id = id
            self.kind = kind
            self.pinned = pinned
        }
    }

    /// Il workspace a cui ancorare un inserimento e il contenitore in cui vive la riga che lo
    /// offre.
    struct Anchor: Equatable {
        let id: UUID
        let container: Container
    }

    /// Righe + slot. `slots.count == rows.count + 1`.
    struct Plan: Equatable {
        let rows: [Row]
        let slots: [Container]

        var count: Int {
            rows.count
        }
    }

    /// Srotola gli elementi (già in ordine visivo: pinned in testa) più la sezione Archive, che è
    /// **sempre** presente in fondo anche a zero archiviati: è la drop zone dell'archiviazione.
    static func plan(
        items: [Item],
        archived: [UUID],
        archiveExpanded: Bool
    ) -> Plan {
        var rows: [Row] = []
        var slots: [Container] = [.root(pinned: items.first?.pinned ?? false)]

        for item in items {
            switch item.kind {
            case .workspace:
                rows.append(.workspace(item.id))
                slots.append(.root(pinned: item.pinned))
            case let .group(members, collapsed):
                rows.append(.groupHeader(item.id))
                // Card chiusa: non ci si rilascia dentro (non vedresti dove atterra), quindi lo
                // slot sotto l'header è già lista.
                slots.append(collapsed ? .root(pinned: item.pinned) : .group(item.id))
                guard !collapsed else { continue }
                for member in members {
                    rows.append(.member(member, group: item.id))
                    slots.append(.group(item.id))
                }
                rows.append(.groupTail(item.id))
                slots.append(.root(pinned: item.pinned))
            }
        }

        rows.append(.archiveHeader)
        slots.append(.archive) // sotto l'header si archivia, anche a sezione chiusa
        if archiveExpanded {
            for id in archived {
                rows.append(.archived(id))
                slots.append(.archive)
            }
        }
        return Plan(rows: rows, slots: slots)
    }
}

extension SidebarLayout.Plan {
    /// Indice di una riga nel piano: la sidebar disegna annidato (le card contengono i membri) ma
    /// misura e calcola su questo indice piatto, unico per tutta la sidebar.
    func index(of row: SidebarLayout.Row) -> Int {
        rows.firstIndex(of: row) ?? 0
    }

    /// Il workspace a cui ancorare un inserimento posato **su questa riga**, e il contenitore in
    /// cui la riga vive. Le righe di un gruppo si ancorano al gruppo; l'header e la coda della card
    /// si ancorano invece al primo/ultimo membro **nella lista**, perché è così che si posa una
    /// riga sopra o sotto una card intera (l'ordine canonico non conosce i gruppi, conosce i
    /// workspace).
    func anchor(at index: Int, items: [SidebarLayout.Item]) -> SidebarLayout.Anchor? {
        guard let row = rows[safe: index] else { return nil }
        switch row {
        case let .workspace(id):
            return SidebarLayout.Anchor(
                id: id,
                container: .root(pinned: pinned(ofItem: id, items: items))
            )
        case let .member(id, group):
            return SidebarLayout.Anchor(id: id, container: .group(group))
        case let .groupHeader(group):
            guard let first = members(of: group, items: items).first else { return nil }
            return SidebarLayout.Anchor(
                id: first, container: .root(pinned: pinned(ofItem: group, items: items))
            )
        case let .groupTail(group):
            guard let last = members(of: group, items: items).last else { return nil }
            return SidebarLayout.Anchor(
                id: last, container: .root(pinned: pinned(ofItem: group, items: items))
            )
        case .archiveHeader:
            return nil
        case let .archived(id):
            return SidebarLayout.Anchor(id: id, container: .archive)
        }
    }

    private func pinned(ofItem id: UUID, items: [SidebarLayout.Item]) -> Bool {
        items.first { $0.id == id }?.pinned ?? false
    }

    private func members(of group: UUID, items: [SidebarLayout.Item]) -> [UUID] {
        guard case let .group(members, _)? = items.first(where: { $0.id == group })?.kind
        else { return [] }
        return members
    }
}
