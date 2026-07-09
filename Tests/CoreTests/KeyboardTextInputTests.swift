import Core
import Testing

@Test func optionGeneratedTextWinsOverShortcuts() {
    let text = KeyboardTextInput.optionGeneratedText(
        characters: "@",
        charactersIgnoringModifiers: "ò",
        hasOption: true,
        hasCommand: false,
        hasControl: false
    )

    #expect(text == "@")
}

@Test func optionGeneratedTextAlsoCoversNumberRowSymbols() {
    let text = KeyboardTextInput.optionGeneratedText(
        characters: "™",
        charactersIgnoringModifiers: "2",
        hasOption: true,
        hasCommand: false,
        hasControl: false
    )

    #expect(text == "™")
}

@Test func commandOrControlKeepsShortcutSemantics() {
    #expect(KeyboardTextInput.optionGeneratedText(
        characters: "@",
        charactersIgnoringModifiers: "ò",
        hasOption: true,
        hasCommand: true,
        hasControl: false
    ) == nil)
    #expect(KeyboardTextInput.optionGeneratedText(
        characters: "@",
        charactersIgnoringModifiers: "ò",
        hasOption: true,
        hasCommand: false,
        hasControl: true
    ) == nil)
}

@Test func nonTextOptionEventsPassThrough() {
    #expect(KeyboardTextInput.optionGeneratedText(
        characters: "",
        charactersIgnoringModifiers: "",
        hasOption: true,
        hasCommand: false,
        hasControl: false
    ) == nil)
    #expect(KeyboardTextInput.optionGeneratedText(
        characters: "\u{F700}",
        charactersIgnoringModifiers: "\u{F700}",
        hasOption: true,
        hasCommand: false,
        hasControl: false
    ) == nil)
}

@Test func unchangedOptionCharactersPassThrough() {
    #expect(KeyboardTextInput.optionGeneratedText(
        characters: "1",
        charactersIgnoringModifiers: "1",
        hasOption: true,
        hasCommand: false,
        hasControl: false
    ) == nil)
}
