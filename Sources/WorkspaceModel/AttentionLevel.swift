/// Livello di attenzione di una tab dopo un completamento. Modella la distinzione tra percezione
/// ("l'ho visto") e risoluzione ("me ne sono occupato"): l'interazione col terminale declassa il
/// segnale da forte a quieto, ma lo spengono solo la ripresa vera della conversazione (prompt ->
/// running), un dismiss esplicito, la chiusura della tab o la decadenza opzionale.
public enum AttentionLevel: String, Sendable, Codable {
    /// Nessun segnale.
    case none
    /// Completato mentre non guardavi: segnale forte (float in sidebar, ring, notifica).
    case unseen
    /// Visto ma mai ripreso ("in sospeso"): segnale quieto e persistente (dashboard, punto dimesso
    /// in sidebar). Sopravvive alla fine della sessione e al riavvio dell'app.
    case pending
}
