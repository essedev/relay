import Foundation
@testable import TerminalHostUI
import Testing

// recency: primo = più recente, ultimo = meno recente.
private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

@Test func noEvictionWhenAtOrUnderCap() {
    let evict = SurfaceEvictionPolicy.evictions(
        recency: [a, b, c],
        keep: a,
        cap: 3,
        isEvictable: { _ in true }
    )
    #expect(evict.isEmpty)
}

@Test func evictsLeastRecentBeyondCap() {
    let evict = SurfaceEvictionPolicy.evictions(
        recency: [a, b, c, d], // a più recente, d meno
        keep: a,
        cap: 2,
        isEvictable: { _ in true }
    )
    #expect(evict == [d, c]) // sfratta i due meno recenti
}

@Test func neverEvictsKeepEvenIfLeastRecent() {
    let evict = SurfaceEvictionPolicy.evictions(
        recency: [a, b, c],
        keep: c, // il meno recente è quello visibile
        cap: 1,
        isEvictable: { _ in true }
    )
    #expect(evict == [b, a]) // c sopravvive, si sfrattano gli altri
    #expect(!evict.contains(c))
}

@Test func skipsNonEvictableAndToleratesOverCap() {
    let evict = SurfaceEvictionPolicy.evictions(
        recency: [a, b, c, d],
        keep: a,
        cap: 1,
        isEvictable: { $0 != c } // c ha lavoro vivo: da tenere
    )
    // d e b sfrattati; c pinnato, a keep -> si resta a 2 (>cap) senza uccidere c.
    #expect(evict == [d, b])
    #expect(!evict.contains(c))
    #expect(!evict.contains(a))
}
