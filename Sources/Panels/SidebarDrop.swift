import Foundation

/// Traduce il rilascio di un drag della sidebar (slot di inserimento nel piano delle righe) in
/// un'azione sullo store: **contenitore di destinazione** (lista con o senza pin, card di un
/// gruppo, archivio) e **ancora di inserimento** nell'ordine canonico. Puro e posizionale, testato
/// senza UI.
///
/// Il contenitore non viene indovinato dai vicini: lo porta scritto lo slot (vedi
/// `SidebarLayout`). Qui resta il lavoro posizionale, cioè tradurre "questo slot" in "prima/dopo
/// questo workspace" nell'array canonico, che i gruppi non li conosce. L'ancora preferisce il
/// vicino **dello stesso contenitore** (la riga si posa esattamente dove indica la linea) e ripiega
/// sul vicino grezzo dello slot.
enum SidebarDrop {
    typealias Container = SidebarLayout.Container
    typealias Row = SidebarLayout.Row
    typealias Item = SidebarLayout.Item

    /// Cosa si sta trascinando: una riga o una card intera. Le card si muovono solo nella lista
    /// (non si annidano e non si archiviano in blocco), quindi il loro slot viene riportato al più
    /// vicino di primo livello.
    enum Dragged: Equatable {
        case workspace(UUID)
        case group(UUID)
    }

    enum Move: Equatable {
        case before(UUID)
        case after(UUID)
    }

    struct Resolution: Equatable {
        /// Dove finisce il trascinato. Il chiamante ne ricava i cambi di campo (pin, gruppo,
        /// archivio); `move` è il riordino nell'array canonico.
        let container: Container
        let move: Move?
    }

    /// Lo slot davvero utilizzabile per ciò che si sta trascinando: per una riga è quello scelto,
    /// per una card è il più vicino di primo livello. Serve anche alla **linea di inserimento**
    /// durante il gesto, così l'anteprima non promette un rilascio che il drop poi non fa.
    static func normalized(insertion: Int, plan: SidebarLayout.Plan, dragged: Dragged) -> Int {
        guard case .group = dragged else { return clamp(insertion, plan: plan) }
        let target = clamp(insertion, plan: plan)
        if case .root = plan.slots[target] { return target }
        // Slot di primo livello più vicino, a parità di distanza quello sopra: una card rilasciata
        // dentro un'altra card si posa accanto, non ci entra.
        let roots = plan.slots.indices.filter {
            if case .root = plan.slots[$0] { true } else { false }
        }
        return roots.min { lhs, rhs in
            let (dl, dr) = (abs(lhs - target), abs(rhs - target))
            return dl == dr ? lhs < rhs : dl < dr
        } ?? target
    }

    static func resolve(
        plan: SidebarLayout.Plan,
        items: [Item],
        dragged: Dragged,
        insertion: Int
    ) -> Resolution? {
        let slot = normalized(insertion: insertion, plan: plan, dragged: dragged)
        let own = ownRows(of: dragged, plan: plan)
        guard let first = own.first, let last = own.last else { return nil }
        // Rilascio negli slot che il trascinato già occupa: nessun effetto.
        guard slot < first || slot > last + 1 else { return nil }
        let container = plan.slots[slot]
        let move = anchor(
            plan: plan, items: items, slot: slot, container: container, excluding: Set(own)
        )
        guard container != currentContainer(of: dragged, plan: plan, items: items) || move != nil
        else { return nil }
        return Resolution(container: container, move: move)
    }

    // MARK: - Interni

    private static func clamp(_ insertion: Int, plan: SidebarLayout.Plan) -> Int {
        max(0, min(insertion, plan.count))
    }

    /// Le righe occupate dal trascinato: una per un workspace, header + membri + coda per una card.
    private static func ownRows(of dragged: Dragged, plan: SidebarLayout.Plan) -> [Int] {
        plan.rows.indices.filter { index in
            switch (plan.rows[index], dragged) {
            case let (.workspace(id), .workspace(dragID)),
                 let (.member(id, _), .workspace(dragID)),
                 let (.archived(id), .workspace(dragID)):
                id == dragID
            case let (.groupHeader(id), .group(dragID)),
                 let (.member(_, id), .group(dragID)),
                 let (.groupTail(id), .group(dragID)):
                id == dragID
            default:
                false
            }
        }
    }

    /// Dove sta ora il trascinato: serve a riconoscere il drop che non cambia niente (stesso
    /// contenitore e nessuno spostamento).
    private static func currentContainer(
        of dragged: Dragged, plan: SidebarLayout.Plan, items: [Item]
    ) -> Container? {
        guard let index = ownRows(of: dragged, plan: plan).first else { return nil }
        switch plan.rows[index] {
        case let .workspace(id):
            return .root(pinned: items.first { $0.id == id }?.pinned ?? false)
        case let .member(_, group):
            return .group(group)
        case let .groupHeader(group):
            return .root(pinned: items.first { $0.id == group }?.pinned ?? false)
        case .archived:
            return .archive
        case .groupTail, .archiveHeader:
            return nil
        }
    }

    /// Ancora canonica per lo slot: prima il vicino **dello stesso contenitore** (in avanti, poi
    /// all'indietro), così la posa coincide con la linea di inserimento; poi il vicino grezzo dello
    /// slot, come ultima risorsa (contenitore appena nato, o vuoto).
    private static func anchor(
        plan: SidebarLayout.Plan,
        items: [Item],
        slot: Int,
        container: Container,
        excluding own: Set<Int>
    ) -> Move? {
        func candidate(_ index: Int) -> SidebarLayout.Anchor? {
            guard !own.contains(index) else { return nil }
            return plan.anchor(at: index, items: items)
        }
        for index in slot ..< plan.count {
            if let found = candidate(index),
               found.container == container { return .before(found.id) }
        }
        for index in stride(from: slot - 1, through: 0, by: -1) {
            if let found = candidate(index),
               found.container == container { return .after(found.id) }
        }
        for index in slot ..< plan.count {
            if let found = candidate(index) { return .before(found.id) }
        }
        for index in stride(from: slot - 1, through: 0, by: -1) {
            if let found = candidate(index) { return .after(found.id) }
        }
        return nil
    }
}
