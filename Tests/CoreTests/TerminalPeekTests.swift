@testable import Core
import Testing

// L'estratto di Home: dallo schermo del terminale, la riga che dice cosa vuole l'agente.

@Test func aQuestionWinsOverTheOptionsBelowIt() {
    let screen = [
        "⏺ Bash(make migrate)",
        "╭──────────────────────────────╮",
        "│ Do you want to proceed?      │",
        "│ ❯ 1. Yes                     │",
        "│   2. No                      │",
        "╰──────────────────────────────╯",
        "",
    ]
    #expect(TerminalPeek.excerpt(from: screen, intent: .question) == "Do you want to proceed?")
}

@Test func anErrorIsFoundAboveThePrompt() {
    let screen = [
        "⏺ Working on it",
        "  ⎿  API Error: 529 overloaded",
        "",
        "╭────────╮",
        "│ >      │",
        "╰────────╯",
        "  ? for shortcuts",
    ]
    #expect(
        TerminalPeek.excerpt(from: screen, intent: .error) == "⎿  API Error: 529 overloaded"
    )
}

@Test func latestSkipsPromptAndHints() {
    let screen = ["⏺ Done. All tests pass.", "", "│ > │", "  esc to interrupt"]
    #expect(TerminalPeek.excerpt(from: screen, intent: .latest) == "⏺ Done. All tests pass.")
}

@Test func anEmptyScreenHasNothingToSay() {
    #expect(TerminalPeek.excerpt(from: ["", "   ", "❯"], intent: .latest) == nil)
}
