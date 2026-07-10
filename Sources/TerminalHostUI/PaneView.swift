import AppKit
import Core

/// Un pane: il terminale di una tab con il **suo** ring di attenzione e, quando il workspace è
/// splittato, un bordo che dice quale pane ha il focus. Senza split c'è un pane solo e il bordo non
/// si accende: non serve indicare il focus quando non c'è scelta.
///
/// Legato alla tab per `tabID`: è la chiave con cui il controller riusa i pane fra un reconcile e
/// l'altro, così un cambio di layout non ricrea le surface (e non uccide i pty).
@MainActor
final class PaneView: NSView {
    let tabID: UUID
    private let ring = AttentionRingView(frame: .zero)
    private let terminal: NSView
    private var focusBorderColor: NSColor?

    /// Respiro attorno al testo. Più stretto dell'inset di una volta (12): con più pane affiancati
    /// quello spazio si sommerebbe due volte al centro. Il container aggiunge il resto sul bordo.
    private static let terminalInset: CGFloat = 6

    init(tabID: UUID, terminal: NSView) {
        self.tabID = tabID
        self.terminal = terminal
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 0

        terminal.translatesAutoresizingMaskIntoConstraints = false
        ring.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        // Il ring sopra il terminale (`hitTest` nil: non intercetta nulla), come nell'area singola.
        addSubview(ring, positioned: .above, relativeTo: terminal)
        let inset = Self.terminalInset
        NSLayoutConstraint.activate([
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            terminal.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            ring.leadingAnchor.constraint(equalTo: leadingAnchor),
            ring.trailingAnchor.constraint(equalTo: trailingAnchor),
            ring.topAnchor.constraint(equalTo: topAnchor),
            ring.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("PaneView is programmatic-only")
    }

    /// La view del terminale, per il first responder e per capire chi possiede un click.
    var terminalView: NSView {
        terminal
    }

    /// Il punto (in coordinate finestra) cade dentro il terminale di questo pane.
    func containsInTerminal(windowPoint: NSPoint) -> Bool {
        terminal.bounds.contains(terminal.convert(windowPoint, from: nil))
    }

    /// Il pane possiede la view che ha il focus di tastiera.
    func owns(responder: NSView) -> Bool {
        responder === terminal || responder.isDescendant(of: terminal)
    }

    func updateRing(color: NSColor?, pulsing: Bool) {
        ring.update(color: color, pulsing: pulsing)
    }

    func flashRing() {
        ring.flash()
    }

    /// Bordo di focus: acceso solo col workspace splittato (`color != nil`), spento sul pane
    /// singolo.
    /// Sta **dentro** al ring di attenzione (che è più esterno), così i due segnali - chi ha il
    /// focus, chi chiede attenzione - restano leggibili insieme invece di sovrapporsi.
    func updateFocusBorder(color: NSColor?) {
        guard focusBorderColor != color else { return }
        focusBorderColor = color
        layer?.borderColor = color?.cgColor
        layer?.borderWidth = color == nil ? 0 : 1
    }

    /// Stacca il terminale prima di buttare via il pane: la surface resta viva nella registry (il
    /// pty non si tocca) e può essere rimontata in un altro pane.
    func detachTerminal() {
        terminal.removeFromSuperview()
    }
}
