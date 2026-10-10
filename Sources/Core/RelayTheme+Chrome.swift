import Foundation

/// I gradini di superficie della chrome, ricavati dal tema e non scelti a mano: la finestra è una
/// cornice un po' più scura del terminale, sidebar e contenuto sono due card sopra di lei, e la
/// card prende luce in alto. Una fonte sola per SwiftUI (`ChromeColors`) e AppKit (la cornice dello
/// split), così su ogni tema le due metà non divergono.
public extension RelayTheme {
    /// La cornice della finestra, attorno alle card: un gradino sotto il fondo del terminale.
    var chromeFrame: RelayColor {
        background.mixed(with: RelayColor(0, 0, 0), isDark ? 0.3 : 0.07)
    }

    /// La luce in cima a una card: il fondo spostato verso il foreground, quanto basta a far
    /// sembrare la card illuminata dall'alto.
    var chromeCardTop: RelayColor {
        background.mixed(with: foreground, isDark ? 0.045 : 0.025)
    }
}
