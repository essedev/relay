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

@Test func relayDarkHasSixteenAnsiColors() {
    // installColors di SwiftTerm ignora l'array se non ha esattamente 16 elementi.
    #expect(RelayTheme.relayDark.ansi.count == 16)
}
