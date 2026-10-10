import AppKit

/// Avvolge una metà della finestra (sidebar o contenuto) in una **card**: bordi arrotondati, un
/// margine verso la cornice, un filo chiaro in cima che la fa sembrare illuminata dall'alto e un
/// contorno appena visibile. Il contenuto resta quello di prima: la card è solo il contenitore.
///
/// Il filo e il contorno stanno in uno strato **sopra** il contenuto (`CardEdgeView`), non in
/// un'ombra della card: lo sfondo delle strip in cima lo coprirebbe, ed era il difetto del concept.
@MainActor
final class CardContainerController: NSViewController {
    /// I margini verso la cornice: il lato che confina con l'altra card resta a zero, lo spazio lo
    /// dà il divider dello split (`FrameSplitView.gap`).
    struct Insets {
        var top: CGFloat
        var leading: CGFloat
        var bottom: CGFloat
        var trailing: CGFloat
    }

    /// Il raggio delle card: un gradino sotto quello della finestra, sopra quello delle righe.
    static let radius: CGFloat = 12

    private let content: NSViewController
    private let insets: Insets
    private var leadingConstraint: NSLayoutConstraint?
    /// Il fondo pieno della card, conservato: `applyTheme` può arrivare prima che la view sia
    /// caricata (lo split la chiama dal suo init), e senza layer il colore andava perso. Era la
    /// cornice scura che si vedeva fra titolo, tab e terminale.
    private var background: NSColor?
    private let clip = NSView()
    private let edge = CardEdgeView()

    init(content: NSViewController, insets: Insets) {
        self.content = content
        self.insets = insets
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("CardContainerController is programmatic-only")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        clip.wantsLayer = true
        clip.layer?.backgroundColor = background?.cgColor
        clip.layer?.cornerRadius = Self.radius
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clip)

        addChild(content)
        let inner = content.view
        inner.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(inner)

        edge.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(edge) // sopra il contenuto: nessuno sfondo può coprirlo

        let leading = clip.leadingAnchor.constraint(
            equalTo: view.leadingAnchor, constant: insets.leading
        )
        leadingConstraint = leading
        NSLayoutConstraint.activate([
            clip.topAnchor.constraint(equalTo: view.topAnchor, constant: insets.top),
            leading,
            clip.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -insets.bottom),
            clip.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -insets.trailing
            ),
            inner.topAnchor.constraint(equalTo: clip.topAnchor),
            inner.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            inner.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            inner.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            edge.topAnchor.constraint(equalTo: clip.topAnchor),
            edge.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            edge.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            edge.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
        ])
    }

    /// Il margine sinistro: la card del contenuto lo prende quando la sidebar si chiude, o
    /// resterebbe incollata al bordo della finestra.
    func setLeadingInset(_ inset: CGFloat) {
        leadingConstraint?.constant = inset
    }

    /// Colori per il tema corrente (il chiamante li ricava da `RelayTheme`). Il fondo pieno serve
    /// alle parti trasparenti del contenuto (lo spazio attorno ai pane): senza, ci passerebbe la
    /// cornice, più scura.
    func applyTheme(background: NSColor, isDark: Bool) {
        self.background = background
        clip.layer?.backgroundColor = background.cgColor
        edge.isDark = isDark
    }
}

/// Il bordo della card: un contorno tenue tutto attorno e un filo più chiaro solo in cima. Puro
/// disegno, non intercetta niente.
@MainActor
private final class CardEdgeView: NSView {
    var isDark = true {
        didSet { needsDisplay = true }
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func draw(_: NSRect) {
        let radius = CardContainerController.radius
        let outline = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius
        )
        (isDark ? NSColor.white.withAlphaComponent(0.04) : NSColor.black.withAlphaComponent(0.08))
            .setStroke()
        outline.lineWidth = 1
        outline.stroke()
        guard isDark else { return }
        // La luce in cima: un filo che si spegne dove la curva dell'angolo scende.
        let top = isFlipped ? bounds.minY + 0.5 : bounds.maxY - 0.5
        let light = NSBezierPath()
        light.move(to: NSPoint(x: bounds.minX + radius, y: top))
        light.line(to: NSPoint(x: bounds.maxX - radius, y: top))
        NSColor.white.withAlphaComponent(0.06).setStroke()
        light.lineWidth = 1
        light.stroke()
    }
}

/// Lo split della finestra con la cornice al posto del divider: lo spazio fra le due card è il
/// divider stesso, del colore della cornice, quindi si continua a trascinarlo per ridimensionare.
@MainActor
final class FrameSplitView: NSSplitView {
    /// Lo spazio fra le card.
    static let gap: CGFloat = 6

    var frameColor: NSColor = .windowBackgroundColor {
        didSet { needsDisplay = true }
    }

    override var dividerThickness: CGFloat {
        Self.gap
    }

    override var dividerColor: NSColor {
        frameColor
    }

    /// Solo il colore della cornice: lo stile di default disegna anche la "fossetta" al centro del
    /// divider, che fra due card sembra una macchia.
    override func drawDivider(in rect: NSRect) {
        frameColor.setFill()
        rect.fill()
    }
}
