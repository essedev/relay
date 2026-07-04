import AppKit
@testable import Panels
import Testing
import WorkspaceModel

// Traduzione NSEvent -> KeyCombo: ogni scorciatoia rimappabile e il recorder ci passano, ma non era
// testata. NSEvent sintetici (come fa PerfSampler) per non dipendere dall'hardware.

private func keyDown(
    chars: String,
    keyCode: UInt16,
    flags: NSEvent.ModifierFlags
) throws -> NSEvent {
    try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: flags,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: chars,
        charactersIgnoringModifiers: chars,
        isARepeat: false,
        keyCode: keyCode
    ))
}

@MainActor @Test func translatesLetterWithModifiers() throws {
    let event = try keyDown(chars: "t", keyCode: 17, flags: [.command])
    #expect(KeyEventBridge.combo(from: event) == KeyCombo(key: "t", modifiers: [.command]))

    let shifted = try keyDown(chars: "j", keyCode: 38, flags: [.command, .shift])
    let combo = KeyCombo(key: "j", modifiers: [.command, .shift])
    #expect(KeyEventBridge.combo(from: shifted) == combo)
}

@MainActor @Test func translatesSpecialKeysByKeyCode() throws {
    // tab = 48, up = 126: il tasto è nominato per keyCode, non per il carattere.
    let tab = try keyDown(chars: "\t", keyCode: 48, flags: [.control])
    #expect(KeyEventBridge.combo(from: tab) == KeyCombo(key: "tab", modifiers: [.control]))

    let up = try keyDown(chars: "", keyCode: 126, flags: [.command, .option])
    #expect(KeyEventBridge.combo(from: up) == KeyCombo(key: "up", modifiers: [.command, .option]))
}

@MainActor @Test func lowercasesLetters() throws {
    // charactersIgnoringModifiers è già minuscolo per le lettere; la combo normalizza comunque.
    let event = try keyDown(chars: "T", keyCode: 17, flags: [.command])
    #expect(KeyEventBridge.combo(from: event)?.key == "t")
}
