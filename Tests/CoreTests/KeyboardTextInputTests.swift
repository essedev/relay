import Core
import Testing

@Test func optionGeneratedTextWinsOverShortcuts() {
    let text = KeyboardTextInput.optionGeneratedText(
        characters: "@",
        charactersIgnoringModifiers: "ò",
        modifiers: [.option]
    )

    #expect(text == "@")
}

@Test func optionDigitsAreReservedForTabSelection() {
    // Option+1..9 è la shortcut fissa di select-tab: vince sul simbolo composto dal layout
    // (es. Option+2 = "™"), quindi la policy non lo considera digitazione.
    for digit in 1 ... 9 {
        #expect(KeyboardTextInput.optionGeneratedText(
            characters: "™",
            charactersIgnoringModifiers: String(digit),
            modifiers: [.option]
        ) == nil)
    }
}

@Test func nonReservedDigitsStayTextEntry() {
    // Lo zero non è una shortcut di select: il testo composto resta digitazione.
    #expect(KeyboardTextInput.optionGeneratedText(
        characters: "‰",
        charactersIgnoringModifiers: "0",
        modifiers: [.option]
    ) == "‰")
}

@Test func shiftedOptionDigitsStayTextEntry() {
    // Con Shift la combo non è il select fisso (che è Option puro): il testo vince.
    #expect(KeyboardTextInput.optionGeneratedText(
        characters: "±",
        charactersIgnoringModifiers: "1",
        modifiers: [.option, .shift]
    ) == "±")
}

@Test func commandOrControlKeepsShortcutSemantics() {
    #expect(KeyboardTextInput.optionGeneratedText(
        characters: "@",
        charactersIgnoringModifiers: "ò",
        modifiers: [.option, .command]
    ) == nil)
    #expect(KeyboardTextInput.optionGeneratedText(
        characters: "@",
        charactersIgnoringModifiers: "ò",
        modifiers: [.option, .control]
    ) == nil)
}

@Test func nonTextOptionEventsPassThrough() {
    #expect(KeyboardTextInput.optionGeneratedText(
        characters: "",
        charactersIgnoringModifiers: "",
        modifiers: [.option]
    ) == nil)
    #expect(KeyboardTextInput.optionGeneratedText(
        characters: "\u{F700}",
        charactersIgnoringModifiers: "\u{F700}",
        modifiers: [.option]
    ) == nil)
}

@Test func unchangedOptionCharactersPassThrough() {
    #expect(KeyboardTextInput.optionGeneratedText(
        characters: "à",
        charactersIgnoringModifiers: "à",
        modifiers: [.option]
    ) == nil)
}

@Test func modifiersFromFlagsMatchesOptionSet() {
    let modifiers = KeyboardTextInput.Modifiers(
        option: true, shift: false, command: true, control: false
    )

    #expect(modifiers == [.option, .command])
}
