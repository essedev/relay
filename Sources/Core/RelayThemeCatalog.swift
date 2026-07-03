/// Catalogo dei temi curati, in coppie dark/light. Il modello (`RelayTheme`) vive in
/// `RelayTheme.swift`; qui solo dati: palette canoniche portate nel formato Relay.
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

    /// Tokyo Night (folke, stile "night"): notturno blu moderno, accenti neon tenui.
    static let tokyoNight = RelayTheme(
        name: "Tokyo Night",
        background: RelayColor(hex: 0x1A1B26),
        foreground: RelayColor(hex: 0xC0CAF5),
        cursor: RelayColor(hex: 0xC0CAF5),
        selection: RelayColor(hex: 0x283457),
        ansi: [
            RelayColor(hex: 0x15161E), // black
            RelayColor(hex: 0xF7768E), // red
            RelayColor(hex: 0x9ECE6A), // green
            RelayColor(hex: 0xE0AF68), // yellow
            RelayColor(hex: 0x7AA2F7), // blue
            RelayColor(hex: 0xBB9AF7), // magenta
            RelayColor(hex: 0x7DCFFF), // cyan
            RelayColor(hex: 0xA9B1D6), // white
            RelayColor(hex: 0x414868), // bright black
            RelayColor(hex: 0xF7768E), // bright red
            RelayColor(hex: 0x9ECE6A), // bright green
            RelayColor(hex: 0xE0AF68), // bright yellow
            RelayColor(hex: 0x7AA2F7), // bright blue
            RelayColor(hex: 0xBB9AF7), // bright magenta
            RelayColor(hex: 0x7DCFFF), // bright cyan
            RelayColor(hex: 0xC0CAF5), // bright white
        ],
        fontName: nil,
        fontSize: 13
    )

    /// Catppuccin Mocha: pastelli lavanda su base scura, il registro "giocoso".
    static let catppuccinMocha = RelayTheme(
        name: "Catppuccin Mocha",
        background: RelayColor(hex: 0x1E1E2E), // base
        foreground: RelayColor(hex: 0xCDD6F4), // text
        cursor: RelayColor(hex: 0xF5E0DC), // rosewater
        selection: RelayColor(hex: 0x45475A), // surface1
        ansi: [
            RelayColor(hex: 0x45475A), // black (surface1)
            RelayColor(hex: 0xF38BA8), // red
            RelayColor(hex: 0xA6E3A1), // green
            RelayColor(hex: 0xF9E2AF), // yellow
            RelayColor(hex: 0x89B4FA), // blue
            RelayColor(hex: 0xF5C2E7), // magenta (pink)
            RelayColor(hex: 0x94E2D5), // cyan (teal)
            RelayColor(hex: 0xBAC2DE), // white (subtext1)
            RelayColor(hex: 0x585B70), // bright black (surface2)
            RelayColor(hex: 0xF38BA8), // bright red
            RelayColor(hex: 0xA6E3A1), // bright green
            RelayColor(hex: 0xF9E2AF), // bright yellow
            RelayColor(hex: 0x89B4FA), // bright blue
            RelayColor(hex: 0xF5C2E7), // bright magenta
            RelayColor(hex: 0x94E2D5), // bright cyan
            RelayColor(hex: 0xA6ADC8), // bright white (subtext0)
        ],
        fontName: nil,
        fontSize: 13
    )

    /// GitHub Dark (Default, palette Primer): near-black ad alto contrasto.
    static let githubDark = RelayTheme(
        name: "GitHub Dark",
        background: RelayColor(hex: 0x0D1117),
        foreground: RelayColor(hex: 0xE6EDF3),
        cursor: RelayColor(hex: 0x58A6FF),
        selection: RelayColor(hex: 0x30363D),
        ansi: [
            RelayColor(hex: 0x484F58), // black
            RelayColor(hex: 0xFF7B72), // red
            RelayColor(hex: 0x3FB950), // green
            RelayColor(hex: 0xD29922), // yellow
            RelayColor(hex: 0x58A6FF), // blue
            RelayColor(hex: 0xBC8CFF), // magenta
            RelayColor(hex: 0x39C5CF), // cyan
            RelayColor(hex: 0xB1BAC4), // white
            RelayColor(hex: 0x6E7681), // bright black
            RelayColor(hex: 0xFFA198), // bright red
            RelayColor(hex: 0x56D364), // bright green
            RelayColor(hex: 0xE3B341), // bright yellow
            RelayColor(hex: 0x79C0FF), // bright blue
            RelayColor(hex: 0xD2A8FF), // bright magenta
            RelayColor(hex: 0x56D4DD), // bright cyan
            RelayColor(hex: 0xFFFFFF), // bright white
        ],
        fontName: nil,
        fontSize: 13
    )

    /// Tokyo Night Day: la controparte chiara, fg blu inchiostro su grigio-azzurro.
    static let tokyoNightDay = RelayTheme(
        name: "Tokyo Night Day",
        background: RelayColor(hex: 0xE1E2E7),
        foreground: RelayColor(hex: 0x3760BF),
        cursor: RelayColor(hex: 0x3760BF),
        selection: RelayColor(hex: 0xB6BFE2),
        ansi: [
            RelayColor(hex: 0xE9E9ED), // black
            RelayColor(hex: 0xF52A65), // red
            RelayColor(hex: 0x587539), // green
            RelayColor(hex: 0x8C6C3E), // yellow
            RelayColor(hex: 0x2E7DE9), // blue
            RelayColor(hex: 0x9854F1), // magenta
            RelayColor(hex: 0x007197), // cyan
            RelayColor(hex: 0x6172B0), // white
            RelayColor(hex: 0xA1A6C5), // bright black
            RelayColor(hex: 0xF52A65), // bright red
            RelayColor(hex: 0x587539), // bright green
            RelayColor(hex: 0x8C6C3E), // bright yellow
            RelayColor(hex: 0x2E7DE9), // bright blue
            RelayColor(hex: 0x9854F1), // bright magenta
            RelayColor(hex: 0x007197), // bright cyan
            RelayColor(hex: 0x3760BF), // bright white
        ],
        fontName: nil,
        fontSize: 13
    )

    /// Catppuccin Latte: pastelli in variante scura su base latte.
    static let catppuccinLatte = RelayTheme(
        name: "Catppuccin Latte",
        background: RelayColor(hex: 0xEFF1F5), // base
        foreground: RelayColor(hex: 0x4C4F69), // text
        cursor: RelayColor(hex: 0xDC8A78), // rosewater
        selection: RelayColor(hex: 0xCCD0DA), // surface0
        ansi: [
            RelayColor(hex: 0x5C5F77), // black (subtext1)
            RelayColor(hex: 0xD20F39), // red
            RelayColor(hex: 0x40A02B), // green
            RelayColor(hex: 0xDF8E1D), // yellow
            RelayColor(hex: 0x1E66F5), // blue
            RelayColor(hex: 0xEA76CB), // magenta (pink)
            RelayColor(hex: 0x179299), // cyan (teal)
            RelayColor(hex: 0xACB0BE), // white (surface2)
            RelayColor(hex: 0x6C6F85), // bright black (subtext0)
            RelayColor(hex: 0xD20F39), // bright red
            RelayColor(hex: 0x40A02B), // bright green
            RelayColor(hex: 0xDF8E1D), // bright yellow
            RelayColor(hex: 0x1E66F5), // bright blue
            RelayColor(hex: 0xEA76CB), // bright magenta
            RelayColor(hex: 0x179299), // bright cyan
            RelayColor(hex: 0xBCC0CC), // bright white (surface1)
        ],
        fontName: nil,
        fontSize: 13
    )

    /// GitHub Light (Default, palette Primer). Unica deviazione dal port upstream: i due gialli
    /// (upstream `#4D2D00`/`#633C01`, marroni quasi neri) usano attention.fg/emphasis di Primer,
    /// così il badge needsInput resta ambra leggibile.
    static let githubLight = RelayTheme(
        name: "GitHub Light",
        background: RelayColor(hex: 0xFFFFFF),
        foreground: RelayColor(hex: 0x24292F),
        cursor: RelayColor(hex: 0x0969DA),
        selection: RelayColor(hex: 0xD0D7DE),
        ansi: [
            RelayColor(hex: 0x24292F), // black
            RelayColor(hex: 0xCF222E), // red
            RelayColor(hex: 0x116329), // green
            RelayColor(hex: 0x9A6700), // yellow (attention.fg)
            RelayColor(hex: 0x0969DA), // blue
            RelayColor(hex: 0x8250DF), // magenta
            RelayColor(hex: 0x1B7C83), // cyan
            RelayColor(hex: 0x6E7781), // white
            RelayColor(hex: 0x57606A), // bright black
            RelayColor(hex: 0xA40E26), // bright red
            RelayColor(hex: 0x1A7F37), // bright green
            RelayColor(hex: 0xBF8700), // bright yellow (attention.emphasis)
            RelayColor(hex: 0x218BFF), // bright blue
            RelayColor(hex: 0xA475F9), // bright magenta
            RelayColor(hex: 0x3192AA), // bright cyan
            RelayColor(hex: 0x8C959F), // bright white
        ],
        fontName: nil,
        fontSize: 13
    )

    /// Temi disponibili (per il picker delle impostazioni), nell'ordine di presentazione: prima gli
    /// scuri, poi i chiari.
    static let all: [RelayTheme] = [
        .relayDark, .solarizedDark, .gruvboxDark, .tokyoNight, .catppuccinMocha, .githubDark,
        .relayLight, .solarizedLight, .gruvboxLight, .tokyoNightDay, .catppuccinLatte, .githubLight,
    ]
}
