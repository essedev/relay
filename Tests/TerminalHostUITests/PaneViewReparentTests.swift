import AppKit
@testable import TerminalHostUI
import Testing

// Con più aree sulla stessa registry (multi-window) la view di un terminale può essere
// riparentata da un'altra area prima che il render della vecchia scatti ("Move to New Window":
// la finestra nuova attacca subito, il detach della vecchia arriva dopo, dal suo Task di
// osservazione). Il detach non deve strappare la view al pane nuovo.

@MainActor
@Test func staleDetachDoesNotStealAReparentedTerminal() {
    let terminal = NSView()
    let old = PaneView(paneID: UUID(), strip: NSView())
    old.attachTerminal(terminal, for: UUID())

    // Un'altra area la riparenta (stessa surface, pane nuovo).
    let new = PaneView(paneID: UUID(), strip: NSView())
    new.attachTerminal(terminal, for: UUID())
    #expect(terminal.superview !== nil)

    // Il detach in ritardo del pane vecchio non deve toccarla: non è più sua.
    old.detachTerminal()
    #expect(terminal.superview != nil, "il pane nuovo è rimasto senza terminale")
    #expect(old.terminalView == nil)
    #expect(new.terminalView === terminal)
}

@MainActor
@Test func detachRemovesATerminalStillOwned() {
    let terminal = NSView()
    let pane = PaneView(paneID: UUID(), strip: NSView())
    pane.attachTerminal(terminal, for: UUID())
    #expect(terminal.superview != nil)

    pane.detachTerminal()
    #expect(terminal.superview == nil)
    #expect(pane.terminalView == nil)
}
