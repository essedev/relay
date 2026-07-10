import Foundation
@testable import TerminalHostUI
import Testing

// Recency: first = most recent, last = least recent.
private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

@Test func noEvictionWhenAtOrUnderCap() {
    let evict = SurfaceEvictionPolicy.evictions(
        recency: [a, b, c],
        keep: [a],
        cap: 3,
        isEvictable: { _ in true }
    )
    #expect(evict.isEmpty)
}

@Test func evictsLeastRecentBeyondCap() {
    let evict = SurfaceEvictionPolicy.evictions(
        recency: [a, b, c, d],
        keep: [a],
        cap: 2,
        isEvictable: { _ in true }
    )
    #expect(evict == [d, c])
}

@Test func neverEvictsKeepEvenIfLeastRecent() {
    let evict = SurfaceEvictionPolicy.evictions(
        recency: [a, b, c],
        keep: [c],
        cap: 1,
        isEvictable: { _ in true }
    )
    #expect(evict == [b, a])
    #expect(!evict.contains(c))
}

@Test func neverEvictsAnyMountedPane() {
    // Con uno split ci sono più terminali a schermo: sfrattarne uno lo lascerebbe bianco davanti
    // agli occhi dell'utente, e ne ucciderebbe la shell.
    let evict = SurfaceEvictionPolicy.evictions(
        recency: [a, b, c, d],
        keep: [c, d], // due pane montati, entrambi vecchi nella recency
        cap: 1,
        isEvictable: { _ in true }
    )
    #expect(evict == [b, a])
}

@Test func skipsProtectedTabsAndEvictsOtherIdleCandidates() {
    let evict = SurfaceEvictionPolicy.evictions(
        recency: [a, b, c, d],
        keep: [a],
        cap: 2,
        isProtected: { $0 == c },
        isEvictable: { _ in true }
    )
    #expect(evict == [d, b])
    #expect(!evict.contains(c))
}

@Test func skipsNonEvictableAndToleratesOverCap() {
    let evict = SurfaceEvictionPolicy.evictions(
        recency: [a, b, c, d],
        keep: [a],
        cap: 1,
        isEvictable: { $0 != c }
    )
    #expect(evict == [d, b])
    #expect(!evict.contains(c))
    #expect(!evict.contains(a))
}

@Test func toleratesOverCapWhenAllCandidatesAreProtected() {
    let evict = SurfaceEvictionPolicy.evictions(
        recency: [a, b, c],
        keep: [a],
        cap: 1,
        isProtected: { $0 == b || $0 == c },
        isEvictable: { _ in true }
    )
    #expect(evict.isEmpty)
}
