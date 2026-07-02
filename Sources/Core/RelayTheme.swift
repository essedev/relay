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
    /// Se il caret lampeggia. Comportamento del cursore, accanto al suo colore (`cursor`). È una
    /// preferenza globale uguale per tutti i temi: il default qui è `false` (caret fisso),
    /// `AppSettings` lo overrida con la scelta utente (come `fontSize`).
    public let cursorBlink: Bool

    public init(
        name: String,
        background: RelayColor,
        foreground: RelayColor,
        cursor: RelayColor,
        selection: RelayColor,
        ansi: [RelayColor],
        fontName: String?,
        fontSize: Double,
        cursorBlink: Bool = false
    ) {
        self.name = name
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.selection = selection
        self.ansi = ansi
        self.fontName = fontName
        self.fontSize = fontSize
        self.cursorBlink = cursorBlink
    }

    /// Vero se il background è scuro (luminanza relativa Rec. 709 < 0.5). Guida l'appearance
    /// AppKit della finestra (darkAqua/aqua), così i controlli di sistema restano leggibili.
    public var isDark: Bool {
        let red = Double(background.red) / 255
        let green = Double(background.green) / 255
        let blue = Double(background.blue) / 255
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue < 0.5
    }

    /// Copia con una dimensione font diversa (lo zoom cambia la size, non il tema).
    public func withFontSize(_ size: Double) -> RelayTheme {
        RelayTheme(
            name: name,
            background: background,
            foreground: foreground,
            cursor: cursor,
            selection: selection,
            ansi: ansi,
            fontName: fontName,
            fontSize: size,
            cursorBlink: cursorBlink
        )
    }

    /// Copia con un font family diverso (preferenza globale sovrapposta al tema; `nil` = monospace
    /// di sistema). Come la size, il font è una scelta utente, non un tratto del tema.
    public func withFontName(_ fontName: String?) -> RelayTheme {
        RelayTheme(
            name: name,
            background: background,
            foreground: foreground,
            cursor: cursor,
            selection: selection,
            ansi: ansi,
            fontName: fontName,
            fontSize: fontSize,
            cursorBlink: cursorBlink
        )
    }

    /// Copia con il blink del caret diverso (preferenza globale sovrapposta al tema).
    public func withCursorBlink(_ enabled: Bool) -> RelayTheme {
        RelayTheme(
            name: name,
            background: background,
            foreground: foreground,
            cursor: cursor,
            selection: selection,
            ansi: ansi,
            fontName: fontName,
            fontSize: fontSize,
            cursorBlink: enabled
        )
    }

    /// Colore ANSI per indice (0-15). Utile alla chrome per derivare i colori dei badge.
    public func ansiColor(_ index: Int) -> RelayColor {
        ansi.indices.contains(index) ? ansi[index] : foreground
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

    /// Tema chiaro curato (famiglia One Light).
    static let relayLight = RelayTheme(
        name: "Relay Light",
        background: RelayColor(hex: 0xFAFAFA),
        foreground: RelayColor(hex: 0x383A42),
        cursor: RelayColor(hex: 0x526FFF),
        selection: RelayColor(hex: 0xD0D0D0),
        ansi: [
            RelayColor(hex: 0x383A42), // black
            RelayColor(hex: 0xE45649), // red
            RelayColor(hex: 0x50A14F), // green
            RelayColor(hex: 0xC18401), // yellow
            RelayColor(hex: 0x4078F2), // blue
            RelayColor(hex: 0xA626A4), // magenta
            RelayColor(hex: 0x0184BC), // cyan
            RelayColor(hex: 0xFAFAFA), // white
            RelayColor(hex: 0xA0A1A7), // bright black
            RelayColor(hex: 0xE45649), // bright red
            RelayColor(hex: 0x50A14F), // bright green
            RelayColor(hex: 0xC18401), // bright yellow
            RelayColor(hex: 0x4078F2), // bright blue
            RelayColor(hex: 0xA626A4), // bright magenta
            RelayColor(hex: 0x0184BC), // bright cyan
            RelayColor(hex: 0xFFFFFF), // bright white
        ],
        fontName: nil,
        fontSize: 13
    )

    /// Solarized Dark (Ethan Schoonover): il classico a bassa saturazione, base03 di sfondo.
    static let solarizedDark = RelayTheme(
        name: "Solarized Dark",
        background: RelayColor(hex: 0x002B36),
        foreground: RelayColor(hex: 0x839496),
        cursor: RelayColor(hex: 0x93A1A1),
        selection: RelayColor(hex: 0x073642),
        ansi: [
            RelayColor(hex: 0x073642), // black (base02)
            RelayColor(hex: 0xDC322F), // red
            RelayColor(hex: 0x859900), // green
            RelayColor(hex: 0xB58900), // yellow
            RelayColor(hex: 0x268BD2), // blue
            RelayColor(hex: 0xD33682), // magenta
            RelayColor(hex: 0x2AA198), // cyan
            RelayColor(hex: 0xEEE8D5), // white (base2)
            RelayColor(hex: 0x002B36), // bright black (base03)
            RelayColor(hex: 0xCB4B16), // bright red (orange)
            RelayColor(hex: 0x586E75), // bright green (base01)
            RelayColor(hex: 0x657B83), // bright yellow (base00)
            RelayColor(hex: 0x839496), // bright blue (base0)
            RelayColor(hex: 0x6C71C4), // bright magenta (violet)
            RelayColor(hex: 0x93A1A1), // bright cyan (base1)
            RelayColor(hex: 0xFDF6E3), // bright white (base3)
        ],
        fontName: nil,
        fontSize: 13
    )

    /// Gruvbox Dark (medium): palette calda retro, molto popolare per il coding.
    static let gruvboxDark = RelayTheme(
        name: "Gruvbox Dark",
        background: RelayColor(hex: 0x282828),
        foreground: RelayColor(hex: 0xEBDBB2),
        cursor: RelayColor(hex: 0xEBDBB2),
        selection: RelayColor(hex: 0x504945),
        ansi: [
            RelayColor(hex: 0x282828), // black (bg0)
            RelayColor(hex: 0xCC241D), // red
            RelayColor(hex: 0x98971A), // green
            RelayColor(hex: 0xD79921), // yellow
            RelayColor(hex: 0x458588), // blue
            RelayColor(hex: 0xB16286), // magenta (purple)
            RelayColor(hex: 0x689D6A), // cyan (aqua)
            RelayColor(hex: 0xA89984), // white (gray)
            RelayColor(hex: 0x928374), // bright black
            RelayColor(hex: 0xFB4934), // bright red
            RelayColor(hex: 0xB8BB26), // bright green
            RelayColor(hex: 0xFABD2F), // bright yellow
            RelayColor(hex: 0x83A598), // bright blue
            RelayColor(hex: 0xD3869B), // bright magenta
            RelayColor(hex: 0x8EC07C), // bright cyan
            RelayColor(hex: 0xEBDBB2), // bright white
        ],
        fontName: nil,
        fontSize: 13
    )

    /// Solarized Light: la controparte chiara, sfondo base3 caldo.
    static let solarizedLight = RelayTheme(
        name: "Solarized Light",
        background: RelayColor(hex: 0xFDF6E3),
        foreground: RelayColor(hex: 0x657B83),
        cursor: RelayColor(hex: 0x586E75),
        selection: RelayColor(hex: 0xEEE8D5),
        ansi: [
            RelayColor(hex: 0xEEE8D5), // black (base2)
            RelayColor(hex: 0xDC322F), // red
            RelayColor(hex: 0x859900), // green
            RelayColor(hex: 0xB58900), // yellow
            RelayColor(hex: 0x268BD2), // blue
            RelayColor(hex: 0xD33682), // magenta
            RelayColor(hex: 0x2AA198), // cyan
            RelayColor(hex: 0x073642), // white (base02)
            RelayColor(hex: 0xFDF6E3), // bright black (base3)
            RelayColor(hex: 0xCB4B16), // bright red (orange)
            RelayColor(hex: 0x93A1A1), // bright green (base1)
            RelayColor(hex: 0x839496), // bright yellow (base0)
            RelayColor(hex: 0x657B83), // bright blue (base00)
            RelayColor(hex: 0x6C71C4), // bright magenta (violet)
            RelayColor(hex: 0x586E75), // bright cyan (base01)
            RelayColor(hex: 0x002B36), // bright white (base03)
        ],
        fontName: nil,
        fontSize: 13
    )

    /// Gruvbox Light: sfondo crema, stessi accenti caldi in variante scura per il testo.
    static let gruvboxLight = RelayTheme(
        name: "Gruvbox Light",
        background: RelayColor(hex: 0xFBF1C7),
        foreground: RelayColor(hex: 0x3C3836),
        cursor: RelayColor(hex: 0x3C3836),
        selection: RelayColor(hex: 0xEBDBB2),
        ansi: [
            RelayColor(hex: 0xFBF1C7), // black (bg0)
            RelayColor(hex: 0xCC241D), // red
            RelayColor(hex: 0x98971A), // green
            RelayColor(hex: 0xD79921), // yellow
            RelayColor(hex: 0x458588), // blue
            RelayColor(hex: 0xB16286), // magenta (purple)
            RelayColor(hex: 0x689D6A), // cyan (aqua)
            RelayColor(hex: 0x7C6F64), // white (gray)
            RelayColor(hex: 0x928374), // bright black
            RelayColor(hex: 0x9D0006), // bright red
            RelayColor(hex: 0x79740E), // bright green
            RelayColor(hex: 0xB57614), // bright yellow
            RelayColor(hex: 0x076678), // bright blue
            RelayColor(hex: 0x8F3F71), // bright magenta
            RelayColor(hex: 0x427B58), // bright cyan
            RelayColor(hex: 0x3C3836), // bright white
        ],
        fontName: nil,
        fontSize: 13
    )

    /// Temi disponibili (per il picker delle impostazioni), nell'ordine di presentazione: prima gli
    /// scuri, poi i chiari.
    static let all: [RelayTheme] = [
        .relayDark, .solarizedDark, .gruvboxDark,
        .relayLight, .solarizedLight, .gruvboxLight,
    ]
}
