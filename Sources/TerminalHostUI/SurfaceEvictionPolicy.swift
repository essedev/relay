import Foundation

/// Decisione pura della LRU sulle surface vive: quali sfrattare per rientrare nel cap. Isolata qui
/// (niente I/O, niente AppKit) così è testabile senza surface reali; `SurfaceRegistry` la applica.
///
/// Regole: si sfratta dai meno recenti; non si sfratta mai il tab da tenere (`keep`, cioè il
/// visibile) né un tab con lavoro vivo (`isEvictable == false`: shell con figli). Se gli evictabili
/// non bastano a rientrare nel cap, si sfratta quel che si può e si resta sopra il cap: meglio
/// sforare che uccidere un processo.
public enum SurfaceEvictionPolicy {
    /// - `recency`: tab con surface viva, dal più recente (primo) al meno recente (ultimo).
    /// - `keep`: tab da non sfrattare mai (il visibile). `nil` se nessuno.
    /// - `cap`: numero massimo di surface vive desiderato.
    /// - `isEvictable`: `false` per i tab con lavoro vivo (da tenere a prescindere).
    public static func evictions(
        recency: [UUID],
        keep: UUID?,
        cap: Int,
        isEvictable: (UUID) -> Bool
    ) -> [UUID] {
        guard cap >= 0, recency.count > cap else { return [] }
        var live = recency.count
        var toEvict: [UUID] = []
        // Dai meno recenti verso i più recenti: sfratta finché non si rientra nel cap.
        for id in recency.reversed() {
            if live <= cap { break }
            if id == keep || !isEvictable(id) { continue }
            toEvict.append(id)
            live -= 1
        }
        return toEvict
    }
}
