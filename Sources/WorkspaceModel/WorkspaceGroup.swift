import Foundation

/// Un gruppo di workspace nella sidebar: una card colorata che raccoglie righe contigue, con un
/// header (titolo + menu) e la possibilità di collassare. Model puro e osservabile, gemello di
/// `Workspace`.
///
/// **L'appartenenza vive sul workspace** (`Workspace.groupID`), non qui: il gruppo non tiene una
/// lista di membri da mantenere in sync con l'array canonico dello store. Di conseguenza la
/// **posizione** del gruppo in sidebar è derivata (quella del suo primo membro nell'ordine
/// canonico) e un gruppo senza membri non è rappresentabile: rimuovere l'ultimo membro lo
/// cancella, come l'ultima tab chiude il workspace.
@Observable
public final class WorkspaceGroup: Identifiable {
    /// Indici ANSI usabili come colore di un gruppo: rosso, verde, giallo, blu, magenta, ciano.
    /// Sono indici nel tema, non colori: la card cambia tinta col tema come badge e ring.
    public static let colorIndices = [1, 2, 3, 4, 5, 6]

    public let id: UUID
    public var name: String
    /// Indice ANSI del tema (vedi `colorIndices`). Fuori range viene riportato dentro alla
    /// lettura, così un file toccato a mano non produce un colore assurdo.
    public var colorIndex: Int
    /// Card chiusa: i membri non si vedono e l'header prende l'altezza di una riga normale, col
    /// conteggio dell'attenzione al posto della lista.
    public var collapsed: Bool
    /// Pin del **blocco**: il gruppo intero sale in testa alla sidebar, sopra i workspace liberi.
    /// È il rimedio all'affondamento: senza, il primo bump di un workspace libero scavalca il
    /// gruppo e da lì in poi il gruppo scende per sempre. Un workspace dentro un gruppo non si
    /// pinna da solo (`Workspace.pinned` viene azzerato all'ingresso): a pinnare è la card.
    public var pinned: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        colorIndex: Int = WorkspaceGroup.colorIndices[0],
        collapsed: Bool = false,
        pinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.collapsed = collapsed
        self.pinned = pinned
    }

    /// Colore normalizzato dentro la palette: un valore fuori range (file editato a mano, formato
    /// futuro) ricade sul primo invece di andare a pescare un ANSI arbitrario.
    public var safeColorIndex: Int {
        Self.colorIndices.contains(colorIndex) ? colorIndex : Self.colorIndices[0]
    }

    /// Colore di default per il prossimo gruppo: gira sulla palette in base a quanti ce ne sono
    /// già, così due gruppi creati di fila non nascono dello stesso colore.
    public static func defaultColorIndex(existing: Int) -> Int {
        colorIndices[existing % colorIndices.count]
    }
}
