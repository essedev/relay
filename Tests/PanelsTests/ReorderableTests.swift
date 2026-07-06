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

@Test func projectedInsertionFollowsDraggedRowCenter() {
    // Righe di 20px: centri a 10, 30, 50.
    let frames: [Int: CGRect] = [
        0: CGRect(x: 0, y: 0, width: 100, height: 20),
        1: CGRect(x: 0, y: 20, width: 100, height: 20),
        2: CGRect(x: 0, y: 40, width: 100, height: 20),
    ]
    // Riga 0 (centro 10) +25 -> proiettato 35, oltre il medio di 1 (30): slot 2.
    #expect(reorderInsertionIndex(
        draggedIndex: 0, translation: 25, frames: frames, axis: .vertical, count: 3
    ) == 2)
    // Poco spostamento (+15 -> 25): resta prima del medio di 1, slot 1.
    #expect(reorderInsertionIndex(
        draggedIndex: 0, translation: 15, frames: frames, axis: .vertical, count: 3
    ) == 1)
    // Riga 2 (centro 50) su di -30 -> proiettato 20, oltre solo il medio di 0: slot 1.
    #expect(reorderInsertionIndex(
        draggedIndex: 2, translation: -30, frames: frames, axis: .vertical, count: 3
    ) == 1)
}

@Test func projectedInsertionIsIndependentOfGrabPoint() {
    // La decisione dipende solo dal centro della riga + traslazione, non da dove l'hai afferrata:
    // stessa riga, stessa traslazione -> stesso slot, sempre. (Era il bug: col puntatore grezzo
    // il risultato slittava di quanto eri lontano dal centro della riga.)
    let frames: [Int: CGRect] = [
        0: CGRect(x: 0, y: 0, width: 100, height: 40),
        1: CGRect(x: 0, y: 40, width: 100, height: 40),
    ]
    // Riga 0 (centro 20) +41 -> proiettato 61, oltre il medio di 1 (60): slot 2.
    #expect(reorderInsertionIndex(
        draggedIndex: 0, translation: 41, frames: frames, axis: .vertical, count: 2
    ) == 2)
}
