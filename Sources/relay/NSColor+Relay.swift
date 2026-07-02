import AppKit
import Core

extension NSColor {
    /// Da colore del tema (dato puro) a NSColor, per la chrome AppKit (finestra, title bar).
    convenience init(relay color: RelayColor) {
        self.init(
            srgbRed: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: 1
        )
    }
}
