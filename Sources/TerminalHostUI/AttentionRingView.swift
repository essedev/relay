import AppKit
import Core

/// Ring colorato attorno al terminale della tab in vista, che ne segnala lo stato agente: verde =
/// completato non visto (statico, con un flash all'accensione e al ritorno in foreground), giallo/
/// rosso pulsante = aspetta input / errore. Overlay puramente visivo: non intercetta eventi
/// (`hitTest` -> nil), il terminale sotto riceve click e tasti.
///
/// Ispirato al notification ring di cmux (ring persistente + flash separato), ma qui il colore
/// codifica lo stato invece del semplice binario letto/non letto.
@MainActor
final class AttentionRingView: NSView {
    private let ringLayer = CAShapeLayer()
    /// Colore corrente del ring, `nil` = spento. Guida `flash` (no-op a ring spento).
    private var isLit = false
    private var isPulsing = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ringLayer.fillColor = nil
        ringLayer.lineWidth = 2.5
        ringLayer.opacity = 0
        ringLayer.shadowOpacity = 0.55
        ringLayer.shadowRadius = 3
        ringLayer.shadowOffset = .zero
        layer?.addSublayer(ringLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("AttentionRingView is programmatic-only")
    }

    /// Overlay decorativo: mai first responder, mai bersaglio di click. Gli eventi passano al
    /// terminale sotto.
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    /// Distanza dello stroke dal bordo esterno della zona (la view coincide col container). L'aria
    /// dal contenuto è la differenza col `terminalInset` (12): 6 qui + 6 di aria interna.
    private static let strokeInset: CGFloat = 6

    override func layout() {
        super.layout()
        ringLayer.frame = bounds
        let rect = bounds.insetBy(dx: Self.strokeInset, dy: Self.strokeInset)
        ringLayer.path = CGPath(roundedRect: rect, cornerWidth: 6, cornerHeight: 6, transform: nil)
    }

    /// Aggiorna il ring per lo stato corrente. `color == nil` lo spegne. `pulsing` = respiro lento
    /// (aspetta input/errore); i completati restano statici (con `flash` a richiamare l'occhio).
    func update(color: NSColor?, pulsing: Bool) {
        ringLayer.removeAnimation(forKey: "pulse")
        ringLayer.removeAnimation(forKey: "flash")
        guard let color else {
            isLit = false
            isPulsing = false
            ringLayer.opacity = 0
            return
        }
        isLit = true
        isPulsing = pulsing
        ringLayer.strokeColor = color.cgColor
        ringLayer.shadowColor = color.cgColor
        ringLayer.opacity = 1
        guard pulsing else { return }
        let breath = CABasicAnimation(keyPath: "opacity")
        breath.fromValue = 1.0
        breath.toValue = 0.35
        breath.duration = 1.0
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ringLayer.add(breath, forKey: "pulse")
    }

    /// Flash momentaneo (doppio blink ~0.9s, come cmux) per richiamare l'occhio su un
    /// completamento:
    /// all'accensione e al ritorno in foreground. No-op se spento o se già pulsa (il pulse basta).
    func flash() {
        guard isLit, !isPulsing else { return }
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 0.2, 1, 0.2, 1]
        blink.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        blink.duration = 0.9
        blink.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
        ]
        ringLayer.add(blink, forKey: "flash")
    }
}

extension NSColor {
    /// Da colore del tema (dato puro) a `NSColor`. Locale a TerminalHostUI: il modulo non dipende
    /// da
    /// AppKit+tema altrove.
    convenience init(relay color: RelayColor) {
        self.init(
            srgbRed: CGFloat(color.red) / 255,
            green: CGFloat(color.green) / 255,
            blue: CGFloat(color.blue) / 255,
            alpha: 1
        )
    }
}
