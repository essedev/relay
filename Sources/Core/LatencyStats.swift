import Foundation

/// Statistiche riassuntive di un campione di latenze (millisecondi). Puro: niente I/O, testabile.
/// Usato dalla strumentazione di performance (misure M3) per riassumere la latenza aggiunta dallo
/// shell sul path di input contro il budget di ARCHITECTURE.md (< 16ms p99).
public struct LatencyStats: Equatable, Sendable {
    public let count: Int
    public let p50: Double
    public let p95: Double
    public let p99: Double
    public let max: Double
    public let mean: Double

    public static let empty = LatencyStats(count: 0, p50: 0, p95: 0, p99: 0, max: 0, mean: 0)

    /// Calcola le statistiche da campioni non ordinati. Vuoto -> `.empty`.
    public init(samples: [Double]) {
        guard !samples.isEmpty else {
            self = .empty
            return
        }
        let sorted = samples.sorted()
        count = sorted.count
        p50 = Self.percentile(sorted, 0.50)
        p95 = Self.percentile(sorted, 0.95)
        p99 = Self.percentile(sorted, 0.99)
        max = sorted[sorted.count - 1]
        mean = sorted.reduce(0, +) / Double(sorted.count)
    }

    private init(count: Int, p50: Double, p95: Double, p99: Double, max: Double, mean: Double) {
        self.count = count
        self.p50 = p50
        self.p95 = p95
        self.p99 = p99
        self.max = max
        self.mean = mean
    }

    /// Percentile con interpolazione lineare tra i due ranghi adiacenti. `sorted` non vuoto e
    /// ordinato crescente; `q` in `0...1`.
    static func percentile(_ sorted: [Double], _ q: Double) -> Double {
        if sorted.count == 1 { return sorted[0] }
        let rank = q * Double(sorted.count - 1)
        let low = Int(rank.rounded(.down))
        let high = Int(rank.rounded(.up))
        if low == high { return sorted[low] }
        let frac = rank - Double(low)
        return sorted[low] + (sorted[high] - sorted[low]) * frac
    }
}
