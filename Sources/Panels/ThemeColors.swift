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

    var secondary: Color {
        Color(theme.ansiColor(8))
    } // bright black (grigio)
    var selection: Color {
        Color(theme.selection)
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
