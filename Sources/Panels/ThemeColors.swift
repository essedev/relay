import Core
import SwiftUI

extension Color {
    /// Da colore del tema (dato puro) a SwiftUI Color.
    init(_ relay: RelayColor) {
        self.init(
            .sRGB,
            red: Double(relay.red) / 255,
            green: Double(relay.green) / 255,
            blue: Double(relay.blue) / 255
        )
    }
}

/// Colori della chrome derivati dal tema corrente, così sidebar/tab bar/badge restano coerenti col
/// terminale. I badge attingono dai colori ANSI del tema (rosso/verde/giallo/blu della palette).
struct ChromeColors {
    let theme: RelayTheme

    init(_ theme: RelayTheme) {
        self.theme = theme
    }

    var background: Color {
        Color(theme.background)
    }

    var foreground: Color {
        Color(theme.foreground)
    }

    /// Da foreground con opacità (non dall'ANSI bright black): contrasto sensato su ogni tema.
    var secondary: Color {
        Color(theme.foreground).opacity(0.6)
    }

    var selection: Color {
        Color(theme.selection)
    }

    /// Hover più tenue della selezione.
    var hover: Color {
        Color(theme.selection).opacity(0.45)
    }

    /// Fondo tenue di un pannello/carta, un gradino sotto `hover`: unifica le tinte `selection`
    /// allo
    /// 0.35 (card della dashboard, pannelli dell'onboarding).
    var surface: Color {
        Color(theme.selection).opacity(0.35)
    }

    var accent: Color {
        Color(theme.ansiColor(4))
    } // blu

    var running: Color {
        Color(theme.ansiColor(4))
    } // blu
    var needsInput: Color {
        Color(theme.ansiColor(3))
    } // giallo/ambra
    var error: Color {
        Color(theme.ansiColor(1))
    } // rosso
    var completed: Color {
        Color(theme.ansiColor(2))
    } // verde
}
