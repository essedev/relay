/// Modello di tema, dato puro (niente AppKit/SwiftUI): è la giuntura del design system. Sia il
/// terminale (`TerminalEngine`, che converte in colori SwiftTerm/NSColor) sia la chrome (`Panels`,
/// che converte in SwiftUI Color) attingono da qui, così un tema resta un'unica fonte.
public struct RelayColor: Sendable, Equatable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Da esadecimale `0xRRGGBB`.
    public init(hex: UInt32) {
        self.init(
            UInt8((hex >> 16) & 0xFF),
            UInt8((hex >> 8) & 0xFF),
            UInt8(hex & 0xFF)
        )
    }
}

/// Un tema completo: colori base del terminale, i 16 ANSI (l'output di Claude Code, git, ls...),
/// e il font. La chrome deriva i suoi colori da qui per restare coerente col terminale.
public struct RelayTheme: Sendable, Equatable {
    public let name: String
    public let background: RelayColor
    public let foreground: RelayColor
    public let cursor: RelayColor
    public let selection: RelayColor
    /// Esattamente 16: 0-7 normali, 8-15 bright (come vuole `installColors` di SwiftTerm).
    public let ansi: [RelayColor]
    /// Nome del font monospace; `nil` = font monospace di sistema (SF Mono).
    public let fontName: String?
    public let fontSize: Double

    public init(
        name: String,
        background: RelayColor,
        foreground: RelayColor,
        cursor: RelayColor,
        selection: RelayColor,
        ansi: [RelayColor],
        fontName: String?,
        fontSize: Double
    ) {
        self.name = name
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.selection = selection
        self.ansi = ansi
        self.fontName = fontName
        self.fontSize = fontSize
    }
}

public extension RelayTheme {
    /// Tema di default: palette dark curata (famiglia One Dark), font monospace di sistema.
    static let relayDark = RelayTheme(
        name: "Relay Dark",
        background: RelayColor(hex: 0x282C34),
        foreground: RelayColor(hex: 0xABB2BF),
        cursor: RelayColor(hex: 0x528BFF),
        selection: RelayColor(hex: 0x3E4451),
        ansi: [
            RelayColor(hex: 0x282C34), // black
            RelayColor(hex: 0xE06C75), // red
            RelayColor(hex: 0x98C379), // green
            RelayColor(hex: 0xE5C07B), // yellow
            RelayColor(hex: 0x61AFEF), // blue
            RelayColor(hex: 0xC678DD), // magenta
            RelayColor(hex: 0x56B6C2), // cyan
            RelayColor(hex: 0xABB2BF), // white
            RelayColor(hex: 0x5C6370), // bright black
            RelayColor(hex: 0xE06C75), // bright red
            RelayColor(hex: 0x98C379), // bright green
            RelayColor(hex: 0xE5C07B), // bright yellow
            RelayColor(hex: 0x61AFEF), // bright blue
            RelayColor(hex: 0xC678DD), // bright magenta
            RelayColor(hex: 0x56B6C2), // bright cyan
            RelayColor(hex: 0xFFFFFF), // bright white
        ],
        fontName: nil,
        fontSize: 13
    )
}
