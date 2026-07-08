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
        copy(fontSize: size)
    }

    /// Copia con un font family diverso (preferenza globale sovrapposta al tema; `nil` = monospace
    /// di sistema). Come la size, il font è una scelta utente, non un tratto del tema.
    public func withFontName(_ fontName: String?) -> RelayTheme {
        copy(fontName: fontName)
    }

    /// Copia con il blink del caret diverso (preferenza globale sovrapposta al tema).
    public func withCursorBlink(_ enabled: Bool) -> RelayTheme {
        copy(cursorBlink: enabled)
    }

    /// Copia sovrascrivendo solo i campi utente (font/blink), elencati una volta sola. `fontName`
    /// è un doppio optional apposta: `.none` = tieni il valore corrente, `.some(x)` = imposta a `x`
    /// (dove `x` può a sua volta essere `nil`, cioè monospace di sistema).
    private func copy(
        fontSize: Double? = nil,
        fontName: String?? = nil,
        cursorBlink: Bool? = nil
    ) -> RelayTheme {
        RelayTheme(
            name: name,
            background: background,
            foreground: foreground,
            cursor: cursor,
            selection: selection,
            ansi: ansi,
            fontName: fontName ?? self.fontName,
            fontSize: fontSize ?? self.fontSize,
            cursorBlink: cursorBlink ?? self.cursorBlink
        )
    }

    /// Colore ANSI per indice (0-15). Utile alla chrome per derivare i colori dei badge.
    public func ansiColor(_ index: Int) -> RelayColor {
        ansi.indices.contains(index) ? ansi[index] : foreground
    }
}
