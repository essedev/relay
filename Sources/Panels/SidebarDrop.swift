import Foundation

/// Traduce il rilascio di un drag della sidebar (indice di inserimento nell'ordine visivo) in
/// un'azione sullo store: eventuale cambio di pin e ancora di inserimento canonica. Pura e
/// posizionale, testata senza UI.
///
/// Modello a due segmenti: l'ordine visivo è pinned in testa, poi il resto, entrambi nell'ordine
/// canonico (nessun float derivato: la posizione è reale). Il drag edita sempre il canonico, senza
/// zone morte. Attraversare il blocco pinned cambia lo stato di pin (dentro = pin, sotto = unpin);
/// il bordo esatto del blocco lo lascia invariato, così niente pin/unpin accidentali. L'ancora
/// preferisce il vicino dello stesso segmento (la riga si posa esattamente dove indica la linea);
/// senza compagni di segmento ripiega sul vicino grezzo dello slot.
enum SidebarDrop {
    /// Riga nell'ordine visivo congelato al momento del drop.
    struct Row: Equatable {
        let id: UUID
        let pinned: Bool

        init(id: UUID, pinned: Bool) {
            self.id = id
            self.pinned = pinned
        }
    }

    enum Move: Equatable {
        case before(UUID)
        case after(UUID)
    }

    struct Resolution: Equatable {
        /// Nuovo stato di pin, solo se cambia.
        let pinned: Bool?
        let move: Move?
    }

    static func resolve(rows: [Row], dragID: UUID, insertion: Int) -> Resolution? {
        guard insertion >= 0, insertion <= rows.count,
              let dragIndex = rows.firstIndex(where: { $0.id == dragID }) else { return nil }
        // Rilascio nello slot di partenza (bordo sopra o sotto di sé): nessun effetto.
        guard insertion != dragIndex, insertion != dragIndex + 1 else { return nil }
        let dragged = rows[dragIndex]
        let prev = insertion > 0 ? rows[insertion - 1] : nil
        let next = insertion < rows.count ? rows[insertion] : nil

        // Pin per regione: sopra una riga pinned si sta solo da pinned; sotto una riga non
        // pinned solo da non pinned. Il bordo del blocco mantiene lo stato corrente.
        let pinned: Bool = if let next, next.pinned {
            true
        } else if let prev, !prev.pinned {
            false
        } else {
            dragged.pinned
        }

        let segment = segmentIndex(pinned: pinned)
        let move = anchor(rows: rows, dragID: dragID, insertion: insertion, segment: segment)
        let pinChange = pinned == dragged.pinned ? nil : pinned
        guard pinChange != nil || move != nil else { return nil }
        return Resolution(pinned: pinChange, move: move)
    }

    /// Segmento visivo: 0 = pinned, 1 = resto (stesso criterio di `orderedWorkspaces`).
    private static func segmentIndex(pinned: Bool) -> Int {
        pinned ? 0 : 1
    }

    /// Ancora canonica per lo slot scelto: prima il vicino del segmento di arrivo (in avanti,
    /// poi all'indietro), così la posa visiva coincide con la linea; altrimenti il vicino grezzo
    /// dello slot.
    private static func anchor(rows: [Row], dragID: UUID, insertion: Int, segment: Int) -> Move? {
        func seg(_ row: Row) -> Int {
            segmentIndex(pinned: row.pinned)
        }
        if let target = rows[insertion...].first(where: { $0.id != dragID && seg($0) == segment }) {
            return .before(target.id)
        }
        if let target = rows[..<insertion].last(where: { $0.id != dragID && seg($0) == segment }) {
            return .after(target.id)
        }
        if insertion < rows.count { return .before(rows[insertion].id) }
        if insertion > 0 { return .after(rows[insertion - 1].id) }
        return nil
    }
}
