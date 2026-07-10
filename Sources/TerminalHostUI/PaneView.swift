import AppKit
import Core

/// Un pane: la **sua** strip di tab (SwiftUI, iniettata dal composition root) sopra, il terminale
/// della tab selezionata sotto, più il ring di attenzione e, con più pane, un bordo che dice chi ha
/// il focus (modello cmux: le tab vivono nei pane).
///
/// Legato al layout per `paneID`: è la chiave con cui il controller riusa i pane fra un reconcile
/// e l'altro. Il terminale dentro si **scambia** quando cambia la tab selezionata della strip: le
/// surface restano vive nella registry (chiavate per `Tab.id`), qui si attacca solo la view.
@MainActor
final class PaneView: NSView {
    let paneID: UUID
    private let strip: NSView
    private let ring = AttentionRingView(frame: .zero)
    private let terminalArea = NSView()
    private(set) var terminal: NSView?
    /// La tab il cui terminale è attaccato ora: il reconcile la confronta con la selezione della
    /// strip per decidere se scambiare.
    private(set) var currentTabID: UUID?
    private var focusBorderColor: NSColor?

    /// Respiro attorno al testo. Più stretto dell'inset di una volta (12): con più pane affiancati
    /// quello spazio si sommerebbe due volte al centro. Il container aggiunge il resto sul bordo.
    private static let terminalInset: CGFloat = 6

    init(paneID: UUID, strip: NSView) {
        self.paneID = paneID
        self.strip = strip
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 0

        strip.translatesAutoresizingMaskIntoConstraints = false
        terminalArea.translatesAutoresizingMaskIntoConstraints = false
        ring.translatesAutoresizingMaskIntoConstraints = false
        addSubview(strip)
        addSubview(terminalArea)
        // Il ring sopra il terminale (`hitTest` nil: non intercetta nulla), attorno alla sola area
        // del terminale: la strip resta fuori dal segnale.
        addSubview(ring, positioned: .above, relativeTo: terminalArea)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: topAnchor),
            strip.leadingAnchor.constraint(equalTo: leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalArea.topAnchor.constraint(equalTo: strip.bottomAnchor),
            terminalArea.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalArea.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalArea.bottomAnchor.constraint(equalTo: bottomAnchor),
            ring.leadingAnchor.constraint(equalTo: terminalArea.leadingAnchor),
            ring.trailingAnchor.constraint(equalTo: terminalArea.trailingAnchor),
            ring.topAnchor.constraint(equalTo: terminalArea.topAnchor),
            ring.bottomAnchor.constraint(equalTo: terminalArea.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("PaneView is programmatic-only")
    }

    /// La view del terminale attaccata, per il first responder e per capire chi possiede un click.
    var terminalView: NSView? {
        terminal
    }

    /// Attacca il terminale di una tab (staccando quello di prima, che resta vivo nella registry).
    /// No-op se è già la tab attaccata.
    func attachTerminal(_ view: NSView, for tabID: UUID) {
        guard currentTabID != tabID || terminal !== view else { return }
        terminal?.removeFromSuperview()
        terminal = view
        currentTabID = tabID
        view.translatesAutoresizingMaskIntoConstraints = false
        terminalArea.addSubview(view)
        let inset = Self.terminalInset
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: terminalArea.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: terminalArea.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: terminalArea.topAnchor, constant: inset),
            view.bottomAnchor.constraint(equalTo: terminalArea.bottomAnchor, constant: -inset),
        ])
    }

    /// Il punto (in coordinate finestra) cade dentro il terminale di questo pane.
    func containsInTerminal(windowPoint: NSPoint) -> Bool {
        guard let terminal else { return false }
        return terminal.bounds.contains(terminal.convert(windowPoint, from: nil))
    }

    /// Il pane possiede la view che ha il focus di tastiera.
    func owns(responder: NSView) -> Bool {
        guard let terminal else { return false }
        return responder === terminal || responder.isDescendant(of: terminal)
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
        terminal?.removeFromSuperview()
        terminal = nil
        currentTabID = nil
    }
}
