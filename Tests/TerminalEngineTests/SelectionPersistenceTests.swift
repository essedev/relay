import AppKit
import SwiftTerm
@testable import TerminalEngine
import Testing

// Una selezione fatta col mouse deve sopravvivere all'output che continua ad arrivare: gli spinner
// dei CLI (`railway login`, `npm install`) riscrivono la loro riga ogni ~100ms, e ogni riscrittura
// arriva come dati dal pty. Se il feed cancella la selezione, copiare da un terminale che "gira" è
// impossibile: si perde prima di arrivare a Cmd+C. L'output passa da `dataReceived`, il percorso
// vero del pty, non da `feed` diretto: è lì che vive il fix.

@MainActor
private func makeView(lines: String...) -> RelayTerminalView {
    let view = RelayTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    for line in lines {
        view.receive(line + "\r\n")
    }
    return view
}

private extension RelayTerminalView {
    func receive(_ text: String) {
        dataReceived(slice: ArraySlice(Array(text.utf8)))
    }
}

@MainActor
@Test func selectionSurvivesOutputThatRewritesTheLine() {
    let view = makeView(lines: "riga uno", "riga due")
    view.selectAll()
    #expect(view.selectionActive)

    // Uno spinner: carriage return + riga riscritta, nessuno scroll.
    view.receive("\rWaiting for sign-in... /")
    #expect(view.selectionActive, "l'output ha cancellato la selezione")
    #expect(view.getSelection() != nil)
}

@MainActor
@Test func selectionSurvivesOutputThatScrolls() {
    let view = makeView(lines: "riga uno", "riga due")
    view.selectAll()

    // Abbastanza da scrollare, non da trimmare lo scrollback (500 righe di default).
    for index in 0 ..< 50 {
        view.receive("riga di output \(index)\r\n")
    }
    #expect(view.selectionActive, "l'output che scrolla ha cancellato la selezione")
}

@MainActor
@Test func selectionClearsWhenScrollbackTrims() {
    let view = makeView(lines: "riga uno", "riga due")
    view.selectAll()

    // Oltre la capienza dello scrollback: il buffer butta le righe più vecchie ma le coordinate
    // della selezione restano dov'erano, quindi coprirebbero altro testo. Meglio azzerarla che
    // lasciare che Cmd+C copi righe mai evidenziate.
    for index in 0 ..< 700 {
        view.receive("riga di output \(index)\r\n")
    }
    #expect(view.getTerminal().buffer.totalLinesTrimmed > 0, "il test non ha trimmato nulla")
    #expect(!view.selectionActive, "selezione preservata su coordinate ormai sbagliate")
}

@MainActor
@Test func selectionClearsWhenSwitchingToAlternateBuffer() {
    let view = makeView(lines: "riga uno", "riga due")
    view.selectAll()

    // Un'app full-screen entra nell'alternate buffer: la selezione puntava al primary.
    view.receive("\u{1b}[?1049h")
    #expect(!view.selectionActive, "selezione preservata attraverso il cambio di buffer")
}

@MainActor
@Test func selectionStillClearsWhenAppOwnsTheMouse() {
    let view = makeView(lines: "riga uno", "riga due")

    // Con mouse tracking attivo (es. Claude Code) la selezione appartiene all'app: il
    // comportamento storico di SwiftTerm resta quello giusto.
    view.receive("\u{1b}[?1000h")
    view.selectAll()
    view.receive("output\r\n")
    #expect(!view.selectionActive)
}

@MainActor
@Test func typingClearsTheSelection() {
    let view = makeView(lines: "riga uno", "riga due")
    view.selectAll()

    // Digitare resta un gesto che scarta la selezione, come in Terminal.app: il fix sull'output
    // non deve renderla appiccicosa.
    let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false,
        keyCode: 0
    )
    if let event { view.keyDown(with: event) }
    #expect(!view.selectionActive)
}
