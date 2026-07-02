@testable import Core
import Testing

@Test func hexInitSplitsChannels() {
    let color = RelayColor(hex: 0x28C0FF)
    #expect(color.red == 0x28)
    #expect(color.green == 0xC0)
    #expect(color.blue == 0xFF)
}

@Test func hexInitHandlesBlackAndWhite() {
    #expect(RelayColor(hex: 0x000000) == RelayColor(0, 0, 0))
    #expect(RelayColor(hex: 0xFFFFFF) == RelayColor(255, 255, 255))
}

@Test func themesHaveSixteenAnsiColors() {
    // installColors di SwiftTerm ignora l'array se non ha esattamente 16 elementi.
    for theme in RelayTheme.all {
        #expect(theme.ansi.count == 16)
    }
}

@Test func registryHasDarkAndLight() {
    #expect(RelayTheme.all.map(\.name) == ["Relay Dark", "Relay Light"])
}

@Test func withFontSizeChangesOnlySize() {
    let resized = RelayTheme.relayDark.withFontSize(20)
    #expect(resized.fontSize == 20)
    #expect(resized.background == RelayTheme.relayDark.background)
    #expect(resized.ansi == RelayTheme.relayDark.ansi)
    #expect(resized.cursorBlink == RelayTheme.relayDark.cursorBlink)
}

@Test func themesDefaultToSteadyCaret() {
    for theme in RelayTheme.all {
        #expect(!theme.cursorBlink)
    }
}

@Test func withCursorBlinkChangesOnlyBlink() {
    let blinking = RelayTheme.relayDark.withCursorBlink(true)
    #expect(blinking.cursorBlink)
    #expect(blinking.fontSize == RelayTheme.relayDark.fontSize)
    #expect(blinking.ansi == RelayTheme.relayDark.ansi)
}

@Test func isDarkFollowsBackgroundLuminance() {
    #expect(RelayTheme.relayDark.isDark)
    #expect(!RelayTheme.relayLight.isDark)
}

@Test func ansiColorClampsOutOfRange() {
    #expect(RelayTheme.relayDark.ansiColor(-1) == RelayTheme.relayDark.foreground)
    #expect(RelayTheme.relayDark.ansiColor(99) == RelayTheme.relayDark.foreground)
}
