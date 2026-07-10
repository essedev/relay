import Foundation

/// Pure LRU decision for live surfaces: which ones to evict to move back toward the cap. Kept
/// separate from I/O and AppKit so `SurfaceRegistry` can apply it while tests exercise the policy
/// without real terminal surfaces.
///
/// Rules: evict from least recent to most recent; never evict `keep`, protected tabs, or tabs with
/// live work (`isEvictable == false`). If the remaining candidates are not enough to reach the cap,
/// tolerate going over budget rather than killing useful context or a live process.
public enum SurfaceEvictionPolicy {
    /// - `recency`: tabs with live surfaces, from most recent (first) to least recent (last).
    /// - `keep`: tabs that must never be evicted: the ones **on screen**. With a split there is
    /// more
    ///   than one visible pane, and evicting any of them would blank a terminal the user is looking
    ///   at (and kill its shell).
    /// - `cap`: desired maximum number of live surfaces.
    /// - `isProtected`: `true` for tabs whose context should survive a soft-cap overflow.
    /// - `isEvictable`: `false` for tabs with live work that must survive regardless of the cap.
    public static func evictions(
        recency: [UUID],
        keep: Set<UUID>,
        cap: Int,
        isProtected: (UUID) -> Bool = { _ in false },
        isEvictable: (UUID) -> Bool
    ) -> [UUID] {
        guard cap >= 0, recency.count > cap else { return [] }
        var live = recency.count
        var toEvict: [UUID] = []
        for id in recency.reversed() {
            if live <= cap { break }
            if keep.contains(id) || isProtected(id) || !isEvictable(id) { continue }
            toEvict.append(id)
            live -= 1
        }
        return toEvict
    }
}
