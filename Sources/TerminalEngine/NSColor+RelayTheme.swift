import AppKit
import Core

public extension NSColor {
    /// Da colore del tema (dato puro) a `NSColor`. Vive in `TerminalEngine` perché è il modulo
    /// AppKit più basso che sia `TerminalHostUI` sia il composition root importano già; `Core` non
    /// può ospitarlo (niente AppKit). Non espone alcun tipo SwiftTerm: la regola di non-leakage
    /// dell'engine resta rispettata.
    convenience init(relay color: RelayColor) {
        self.init(
            srgbRed: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: 1
        )
    }
}
