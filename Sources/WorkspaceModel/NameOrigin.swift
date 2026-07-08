import Foundation

/// Origine del nome di un workspace: guida la nomina automatica (`NamingController` nel composition
/// root). Persistito nello snapshot come stringa; campo additivo, i layout salvati prima della
/// feature decodificano a `.user` (i nomi esistenti sono conosciuti dall'utente, rinominarli al
/// primo avvio post-upgrade sarebbe ostile).
public enum NameOrigin: String, Codable, Sendable, Equatable {
    /// Placeholder ("Workspace N") o nome derivato dalla cartella aperta: **eleggibile** alla
    /// generazione automatica di un nome più parlante.
    case `default`
    /// Nome prodotto dalla nomina automatica. One-shot: non si rigenera da solo (solo un
    /// "Regenerate name" esplicito lo rifà), così l'app non litiga col nome che ha appena scelto.
    case generated
    /// Rinominato a mano dall'utente: intoccabile, mai sovrascritto dalla nomina automatica.
    case user
}
