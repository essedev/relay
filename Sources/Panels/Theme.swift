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

    public enum Colors {
        public static let selection = Color.accentColor.opacity(0.18)
        public static let accent = Color.accentColor
        public static let secondary = Color.secondary
        public static let separator = Color(nsColor: .separatorColor)
        public static let tabBarBackground = Color(nsColor: .underPageBackgroundColor)
    }

    public enum Typography {
        public static let title = Font.system(size: 13, weight: .semibold)
        public static let item = Font.system(size: 13)
        public static let tab = Font.system(size: 12)
    }

    public enum Metrics {
        public static let tabBarHeight: CGFloat = 34
    }
}
