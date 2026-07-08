import AppKit
import Panels

/// Contenitore root: il contenuto (split view) riempie la finestra e l'overlay (toggle sidebar)
/// sta a posizione fissa accanto ai semafori, sopra tutto. Scelto al posto della titlebar
/// accessory, che con `titleVisibility = .hidden` su macOS 26 non viene renderizzata.
@MainActor
final class RootOverlayController: NSViewController {
    private let content: NSViewController
    private let overlay: NSView
    private var overlayLeading: NSLayoutConstraint?
    private var lastKnownSidebarWidth: CGFloat = 0
    /// Overlay full-window corrente (dashboard): sopra tutto, uno alla volta.
    private var fullOverlay: NSView?
    /// Spazio orizzontale dei semafori: l'overlay non va mai più a sinistra di così.
    private static let trafficLightsInset: CGFloat = 78

    init(content: NSViewController, overlay: NSView) {
        self.content = content
        self.overlay = overlay
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("RootOverlayController is programmatic-only")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        addChild(content)
        let contentView = content.view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)

        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)

        let leading = overlay.leadingAnchor.constraint(
            equalTo: view.leadingAnchor,
            constant: Self.trafficLightsInset
        )
        overlayLeading = leading
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leading,
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.heightAnchor.constraint(equalToConstant: Theme.Metrics.titleBarHeight),
        ])
        // Riallinea con l'ultima larghezza vista: i resize dello split possono precedere il load.
        sidebarWidthDidChange(lastKnownSidebarWidth)
    }

    /// Monta un overlay a tutta finestra sopra qualunque cosa (dashboard, onboarding). Uno alla
    /// volta: un overlay nuovo sostituisce il precedente. L'overlay viene avvolto in un container
    /// che chiude i buchi di hit-testing (vedi `FullOverlayContainerView`) e, finché è su, le
    /// cursor rects della finestra sono disattivate: quelle del terminale sotto
    /// (`addCursorRect(_:cursor:)` di SwiftTerm) non rispettano l'occlusione e terrebbero
    /// l'I-beam sopra l'overlay.
    func presentFullOverlay(_ overlayView: NSView) {
        dismissFullOverlay()
        let container = FullOverlayContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(overlayView)
        view.addSubview(container) // ultimo aggiunto = sopra contenuto e toggle sidebar
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: container.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        fullOverlay = container
        view.window?.disableCursorRects()
        NSCursor.arrow.set() // il cursore corrente può essere l'I-beam del terminale
    }

    func dismissFullOverlay() {
        guard let fullOverlay else { return }
        fullOverlay.removeFromSuperview()
        self.fullOverlay = nil
        view.window?.enableCursorRects()
        view.window?.resetCursorRects() // ricostruisce le rects del contenuto tornato scoperto
    }

    /// Container degli overlay full-window: chiude i buchi di hit-testing della hosting SwiftUI.
    /// Dove il contenuto non è hit-testable `hitTest` tornerebbe `nil` e mouse e cursor update
    /// cadrebbero sulle view sotto (selezione di testo nel terminale con l'overlay aperto,
    /// cursore I-beam): il fallback è il container stesso, che consuma il mouse e tiene il
    /// cursore freccia.
    private final class FullOverlayContainerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            if let hit = super.hitTest(point) { return hit }
            let local = convert(point, from: superview)
            return bounds.contains(local) ? self : nil
        }

        override func cursorUpdate(with _: NSEvent) {
            NSCursor.arrow.set()
        }

        // Zone morte dell'overlay: il mouse muore qui, non passa al contenuto sotto.
        override func mouseDown(with _: NSEvent) {}
        override func mouseDragged(with _: NSEvent) {}
        override func mouseUp(with _: NSEvent) {}
    }

    /// Segue la larghezza corrente della sidebar (chiamato a ogni resize, anche frame-by-frame
    /// durante l'animazione del collasso): l'overlay sta al bordo destro della sidebar quando è
    /// aperta e scivola fino ai semafori quando si chiude. Un solo bottone, sempre in continuità.
    /// I primi resize dello split possono arrivare prima di `viewDidLoad`: no-op finché il
    /// constraint non esiste (il layout iniziale riallinea comunque).
    func sidebarWidthDidChange(_ width: CGFloat) {
        lastKnownSidebarWidth = width
        guard let overlayLeading else { return }
        let trailingAligned = width - overlay.fittingSize.width - Theme.Spacing.xs
        overlayLeading.constant = max(Self.trafficLightsInset, trailingAligned)
    }
}
