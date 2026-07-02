@testable import Core
import Testing

@Test func emptySamplesGiveEmptyStats() {
    let stats = LatencyStats(samples: [])
    #expect(stats == .empty)
    #expect(stats.max == 0)
}

@Test func singleSampleIsEveryPercentile() {
    let stats = LatencyStats(samples: [4.2])
    #expect(stats.count == 1)
    #expect(stats.p50 == 4.2)
    #expect(stats.p99 == 4.2)
    #expect(stats.max == 4.2)
    #expect(stats.mean == 4.2)
}

@Test func percentilesOnKnownDistribution() {
    // 1...100: mediana ~50.5, p99 ~99.01, max 100.
    let stats = LatencyStats(samples: (1 ... 100).map(Double.init))
    #expect(stats.count == 100)
    #expect(abs(stats.p50 - 50.5) < 0.001)
    #expect(abs(stats.p99 - 99.01) < 0.001)
    #expect(stats.max == 100)
    #expect(abs(stats.mean - 50.5) < 0.001)
}

@Test func statsIgnoreInputOrder() {
    let ordered = LatencyStats(samples: [1, 2, 3, 4, 5])
    let shuffled = LatencyStats(samples: [3, 1, 5, 2, 4])
    #expect(ordered == shuffled)
}

@Test func percentileInterpolatesBetweenRanks() {
    // Due campioni: p50 sta a metà tra i due (interpolazione lineare).
    #expect(LatencyStats.percentile([10, 20], 0.5) == 15)
    #expect(LatencyStats.percentile([10, 20], 0.0) == 10)
    #expect(LatencyStats.percentile([10, 20], 1.0) == 20)
}
