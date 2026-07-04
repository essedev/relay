@testable import TerminalEngine
import Testing

@Test func wholeDeltaEmitsImmediately() {
    var acc = PreciseScrollAccumulator()
    #expect(acc.lines(addingDeltaInRows: 2.0) == 2)
    #expect(acc.lines(addingDeltaInRows: -3.0) == -3)
}

@Test func fractionalDeltasAccumulate() {
    var acc = PreciseScrollAccumulator()
    #expect(acc.lines(addingDeltaInRows: 0.4) == 0)
    #expect(acc.lines(addingDeltaInRows: 0.4) == 0)
    #expect(acc.lines(addingDeltaInRows: 0.4) == 1)
}

@Test func residualCarriesAcrossEvents() {
    var acc = PreciseScrollAccumulator()
    #expect(acc.lines(addingDeltaInRows: 1.5) == 1)
    #expect(acc.lines(addingDeltaInRows: 0.5) == 1)
}

@Test func negativeResidualCarries() {
    var acc = PreciseScrollAccumulator()
    #expect(acc.lines(addingDeltaInRows: -1.5) == -1)
    #expect(acc.lines(addingDeltaInRows: -0.5) == -1)
}

@Test func directionChangeDropsResidual() {
    var acc = PreciseScrollAccumulator()
    #expect(acc.lines(addingDeltaInRows: 0.9) == 0)
    // Senza reset il residuo +0.9 assorbirebbe il -1.0 (0.9 - 1.0 = -0.1 -> 0 righe).
    #expect(acc.lines(addingDeltaInRows: -1.0) == -1)
}

@Test func zeroDeltaIsIgnoredAndKeepsResidual() {
    var acc = PreciseScrollAccumulator()
    #expect(acc.lines(addingDeltaInRows: 0.6) == 0)
    #expect(acc.lines(addingDeltaInRows: 0.0) == 0)
    #expect(acc.lines(addingDeltaInRows: 0.6) == 1)
}

@Test func nonFiniteDeltaIsIgnored() {
    var acc = PreciseScrollAccumulator()
    #expect(acc.lines(addingDeltaInRows: .nan) == 0)
    #expect(acc.lines(addingDeltaInRows: .infinity) == 0)
    #expect(acc.lines(addingDeltaInRows: 1.0) == 1)
}
