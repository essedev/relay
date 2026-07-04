import Foundation
@testable import Panels
import Testing

// Index math del riordino drag & drop: pura ma non testata (il bug del drop a fine segmento vive
// nel chiamante, ma questa è la primitiva che sceglie lo slot).

@Test func insertionIndexPicksSlotByMidpoint() {
    let frames: [Int: CGRect] = [
        0: CGRect(x: 0, y: 0, width: 100, height: 20),
        1: CGRect(x: 0, y: 20, width: 100, height: 20),
        2: CGRect(x: 0, y: 40, width: 100, height: 20),
    ]
    // Sopra il punto medio della riga 0 -> inserisci in testa.
    #expect(reorderInsertionIndex(
        location: CGPoint(x: 50, y: 5), frames: frames, axis: .vertical, count: 3
    ) == 0)
    // Oltre il medio di 0 ma prima del medio di 1 -> slot 1.
    #expect(reorderInsertionIndex(
        location: CGPoint(x: 50, y: 15), frames: frames, axis: .vertical, count: 3
    ) == 1)
    // Oltre tutti i punti medi -> in coda.
    #expect(reorderInsertionIndex(
        location: CGPoint(x: 50, y: 100), frames: frames, axis: .vertical, count: 3
    ) == 3)
}

@Test func insertionIndexHorizontalUsesX() {
    let frames: [Int: CGRect] = [
        0: CGRect(x: 0, y: 0, width: 30, height: 20),
        1: CGRect(x: 30, y: 0, width: 30, height: 20),
    ]
    #expect(reorderInsertionIndex(
        location: CGPoint(x: 5, y: 10), frames: frames, axis: .horizontal, count: 2
    ) == 0)
    #expect(reorderInsertionIndex(
        location: CGPoint(x: 55, y: 10), frames: frames, axis: .horizontal, count: 2
    ) == 2)
}

@Test func insertionIndexIgnoresMissingFrames() {
    // Frame non ancora raccolti (LazyVStack): la funzione salta gli indici senza frame.
    let frames: [Int: CGRect] = [1: CGRect(x: 0, y: 20, width: 100, height: 20)]
    #expect(reorderInsertionIndex(
        location: CGPoint(x: 50, y: 100), frames: frames, axis: .vertical, count: 3
    ) == 2)
}
