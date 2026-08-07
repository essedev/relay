import Foundation
@testable import Panels
import Testing

// L'unica regola che decide dove finisce una sessione viva quando la trascini fuori dalla sua
// strip: quale riga della sidebar sta sotto il puntatore.

private let rowA = UUID()
private let rowB = UUID()

private let frameA = CGRect(x: 0, y: 0, width: 200, height: 40)
private let frameB = CGRect(x: 0, y: 40, width: 200, height: 40)
private let rows: [UUID: CGRect] = [rowA: frameA, rowB: frameB]

@Test func hitPicksTheRowUnderThePoint() {
    #expect(TabDropTargets.hit(CGPoint(x: 100, y: 20), in: rows, excluding: nil) == rowA)
    #expect(TabDropTargets.hit(CGPoint(x: 100, y: 60), in: rows, excluding: nil) == rowB)
}

@Test func hitIgnoresPointsOutsideEveryRow() {
    #expect(TabDropTargets.hit(CGPoint(x: 100, y: 200), in: rows, excluding: nil) == nil)
    #expect(TabDropTargets.hit(CGPoint(x: 400, y: 20), in: rows, excluding: nil) == nil)
}

@Test func hitSkipsTheWorkspaceTheTabCameFrom() {
    // Rilasciare la tab sulla riga da cui è partita non è uno spostamento: nessun bersaglio,
    // così il rilascio ricade sul riordino nella strip.
    #expect(TabDropTargets.hit(CGPoint(x: 100, y: 20), in: rows, excluding: rowA) == nil)
    #expect(TabDropTargets.hit(CGPoint(x: 100, y: 60), in: rows, excluding: rowA) == rowB)
}

@Test func hitIsStableWhenRowsOverlap() {
    // Non dovrebbe succedere (le righe non si sovrappongono), ma il risultato non deve dipendere
    // dall'ordine di iterazione di un dizionario: vince il centro più vicino.
    let wide = UUID()
    let overlapping = rows.merging([wide: CGRect(x: 0, y: 0, width: 200, height: 400)]) { a, _ in
        a
    }
    let point = CGPoint(x: 100, y: 20)
    #expect(TabDropTargets.hit(point, in: overlapping, excluding: nil) == rowA)
    #expect(TabDropTargets.hit(point, in: overlapping, excluding: rowA) == wide)
}

@MainActor @Test func sessionHasNoTargetUntilTheDragLeavesTheStrip() {
    let session = TabDragSession()
    session.setSidebarRect(CGRect(x: 0, y: 0, width: 200, height: 400))
    session.setTarget(rowA, frame: frameA)
    session.begin(TabDragSession.Payload(
        tabID: UUID(), sourceWorkspaceID: rowB, title: "claude"
    ))

    session.move(to: CGPoint(x: 100, y: 20), outside: false)
    #expect(session.target == nil)

    session.move(to: CGPoint(x: 100, y: 20), outside: true)
    #expect(session.target == rowA)
}

@MainActor @Test func sessionIgnoresRowsWhenThePointerIsOutsideTheSidebar() {
    let session = TabDragSession()
    // Sidebar collassata: i frame delle righe sono ancora quelli dell'ultimo layout, ma nessun
    // punto può cadere dentro una sidebar larga zero.
    session.setSidebarRect(CGRect(x: 0, y: 0, width: 0, height: 400))
    session.setTarget(rowA, frame: frameA)
    session.begin(TabDragSession.Payload(
        tabID: UUID(), sourceWorkspaceID: rowB, title: "claude"
    ))
    session.move(to: CGPoint(x: 100, y: 20), outside: true)

    #expect(session.target == nil)
}

@MainActor @Test func endClearsTheSessionAndReportsTheTarget() {
    let session = TabDragSession()
    var ghostVisible: [Bool] = []
    session.onGhostVisibilityChange = { ghostVisible.append($0) }
    session.setSidebarRect(CGRect(x: 0, y: 0, width: 200, height: 400))
    session.setTarget(rowA, frame: frameA)
    session.begin(TabDragSession.Payload(
        tabID: UUID(), sourceWorkspaceID: rowB, title: "claude"
    ))
    session.move(to: CGPoint(x: 100, y: 20), outside: true)

    #expect(session.end() == rowA)
    #expect(session.payload == nil)
    #expect(session.isOutside == false)
    #expect(ghostVisible == [true, false])
    // Un secondo end (gesto annullato dopo onEnded) non deve rimettere in scena il fantasma.
    #expect(session.end() == nil)
    #expect(ghostVisible == [true, false])
}

@MainActor @Test func pruneDropsRowsThatLeftTheSidebar() {
    let session = TabDragSession()
    session.setTarget(rowA, frame: frameA)
    session.setTarget(rowB, frame: frameB)

    session.pruneTargets(keeping: [rowB])

    #expect(session.targets.keys.sorted { $0.uuidString < $1.uuidString } == [rowB])
}
