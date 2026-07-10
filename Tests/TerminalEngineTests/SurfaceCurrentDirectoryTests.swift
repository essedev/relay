import Foundation
@testable import TerminalEngine
import Testing

// Integrazione sul pty vero (niente mock: le divergenze mock/reale mascherano proprio il bug che
// questo copre). La surface deve riportare la cwd **viva** della shell, anche quando nessun OSC 7
// viene emesso - il caso di default in Relay, che non setta `TERM_PROGRAM`.

/// Aspetta che `condition` diventi vera, fino a `timeout`. La shell impiega qualche decina di ms ad
/// avviarsi e a eseguire il `cd`: un `sleep` fisso sarebbe o lento o flaky.
@MainActor
private func eventually(
    timeout: Duration = .seconds(5),
    _ condition: () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

@MainActor
@Test func surfaceReportsShellWorkingDirectoryAfterCd() async {
    // `/usr/local` esiste su ogni macOS e non è la home: distingue il `cd` dalla cwd di partenza.
    let target = "/usr/local"
    let start = NSHomeDirectory()
    #expect(start != target)

    let surface = SwiftTermEngine().makeSurface(cwd: start, shell: nil, env: [:])
    defer { surface.teardown() }
    surface.start()

    let booted = await eventually { surface.currentDirectory() == start }
    #expect(booted, "la shell non ha riportato la cwd di partenza")

    surface.sendText("cd \(target)\n")

    // Il cuore del fix: senza OSC 7 l'app non saprebbe del `cd`; leggendo il processo sì.
    let followed = await eventually { surface.currentDirectory() == target }
    #expect(followed, "la cwd letta dalla shell non ha seguito il cd")
}

@MainActor
@Test func unstartedSurfaceHasNoWorkingDirectory() {
    // Tab non realizzata (surface mai avviata, o sfrattata dal cap LRU): nessuna shell da leggere,
    // quindi `nil`. È ciò che lascia vincere l'ultima cwd nota in `Core.CurrentDirectory`.
    let surface = SwiftTermEngine().makeSurface(cwd: NSHomeDirectory(), shell: nil, env: [:])
    defer { surface.teardown() }

    #expect(surface.currentDirectory() == nil)
}
