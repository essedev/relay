import SwiftUI

/// Design system minimo (principio UI #6): i pannelli attingono a questi token invece di valori
/// hardcoded, così alzare l'asticella estetica è un cambio di token, non un refactor.
public enum Theme {
    public enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
    }

    public enum Radius {
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 8
    }

    // Nota: niente enum Colors statico. I colori della chrome derivano dal tema corrente via
    // `ChromeColors` (vedi ThemeColors.swift): un'unica fonte, coerente col terminale.

    public enum Typography {
        public static let title = Font.system(size: 13, weight: .semibold)
        public static let item = Font.system(size: 13)
        public static let tab = Font.system(size: 12)
        public static let windowTitle = Font.system(size: 12, weight: .medium)
        public static let subtitle = Font.system(size: 11)
        public static let caption = Font.system(size: 10, weight: .medium)
        /// Etichetta di sezione / piccola affordance a peso semibold (header sidebar, icone
        /// find/resume). Fratello semibold di `subtitle`.
        public static let sectionHeader = Font.system(size: 11, weight: .semibold)
        /// Icona di testa in una riga di lista/impostazioni (pin, cartella, categoria, radio tema).
        public static let rowIcon = Font.system(size: 12)
    }

    public enum Metrics {
        public static let tabBarHeight: CGFloat = 34
        /// Altezza della strip del titolo (allineata verticalmente ai semafori della finestra).
        public static let titleBarHeight: CGFloat = 30
        /// Larghezza massima di una tab: un titolo OSC lungo (Claude manda il nome della chat) non
        /// deve allargare la tab oltre la finestra; il testo si tronca.
        public static let maxTabWidth: CGFloat = 180
        /// Pallino di stato: dimensione piena (badge agente), compatta (card dashboard, righe
        /// impostazioni), pallino di presenza (accento), spessore dell'anello vuoto.
        public static let statusDot: CGFloat = 8
        public static let statusDotCompact: CGFloat = 7
        public static let presenceDot: CGFloat = 6
        public static let statusRingWidth: CGFloat = 1.5
    }
}
