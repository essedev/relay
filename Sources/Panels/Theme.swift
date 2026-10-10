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
        public static let xl: CGFloat = 24
        /// Margine laterale delle pagine (Home, Projects).
        public static let page: CGFloat = 40
    }

    public enum Radius {
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 8
        /// Righe e campi delle pagine, un gradino sopra le righe della sidebar.
        public static let lg: CGFloat = 10
    }

    // Nota: niente enum Colors statico. I colori della chrome derivano dal tema corrente via
    // `ChromeColors` (vedi ThemeColors.swift): un'unica fonte, coerente col terminale.

    public enum Typography {
        public static let title = Font.system(size: 13, weight: .semibold)
        /// Titolo di una pagina: dice la situazione ("3 sessions need you"), non il nome del posto.
        public static let pageTitle = Font.system(size: 24, weight: .semibold)
        /// Riga di sottotitolo di una pagina.
        public static let pageSubtitle = Font.system(size: 13)
        /// Titolo di una sezione di pagina.
        public static let pageHeading = Font.system(size: 13, weight: .semibold)
        /// Estratto di terminale (ultima riga dell'agente) dentro una pagina.
        public static let excerpt = Font.system(size: 11.5, design: .monospaced)
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

    public enum Opacity {
        /// Fondo di una pulsazione: quanto si smorza ciò che pulsa (badge che chiede attenzione,
        /// nome di un workspace in corso di generazione).
        public static let pulseFloor: Double = 0.35
    }

    /// Movimento condiviso: le durate stanno qui e non nelle view, come i colori.
    public enum Motion {
        /// Pulsazione lenta e continua: "sta succedendo qualcosa", senza urgenza.
        public static let pulse = Animation.easeInOut(duration: 0.8).repeatForever(
            autoreverses: true
        )
        /// Ritorno a riposo quando la pulsazione finisce: corto, così la fine si nota.
        public static let settle = Animation.easeOut(duration: 0.2)
    }

    public enum Metrics {
        public static let tabBarHeight: CGFloat = 34
        /// Altezza della strip del titolo in cima a ogni card, allineata ai semafori: con la
        /// toolbar `.unified` stanno centrati a 26 punti dal bordo della finestra, cioè a 20 dal
        /// bordo della card (margine 6): una strip di 40 li ha sulla sua mezzeria.
        public static let titleBarHeight: CGFloat = 40
        /// Larghezza massima di una tab: un titolo OSC lungo (Claude manda il nome della chat) non
        /// deve allargare la tab oltre la finestra; il testo si tronca.
        public static let maxTabWidth: CGFloat = 180
        /// Larghezza massima del contenuto di una pagina: righe leggibili, e l'azione di una riga
        /// resta vicina al testo che la motiva invece di finire a un metro.
        public static let pageMaxWidth: CGFloat = 760
        /// Pallino di stato: dimensione piena (badge agente), compatta (card dashboard, righe
        /// impostazioni), pallino di presenza (accento), spessore dell'anello vuoto.
        public static let statusDot: CGFloat = 8
        public static let statusDotCompact: CGFloat = 7
        public static let presenceDot: CGFloat = 6
        public static let statusRingWidth: CGFloat = 1.5
    }
}
