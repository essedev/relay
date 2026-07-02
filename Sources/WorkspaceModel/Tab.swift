import Foundation

/// Una tab dentro un workspace. V0: una tab = un terminale (identificato da `id`).
/// La gerarchia a split (pane tree) potrà appendersi qui in futuro senza cambiare l'API esterna.
@Observable
public final class Tab: Identifiable {
    public let id: UUID
    public var title: String
    /// L'utente ha rinominato la tab: non sovrascrivere il titolo con l'OSC del programma.
    public var hasCustomTitle: Bool

    public init(id: UUID = UUID(), title: String = "shell", hasCustomTitle: Bool = false) {
        self.id = id
        self.title = title
        self.hasCustomTitle = hasCustomTitle
    }
}
