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
    }

    public enum Metrics {
        public static let tabBarHeight: CGFloat = 34
        /// Altezza della strip del titolo (allineata verticalmente ai semafori della finestra).
        public static let titleBarHeight: CGFloat = 30
        /// Spazio orizzontale occupato dai semafori: l'header della sidebar parte dopo.
        public static let trafficLightsInset: CGFloat = 76
    }
}
