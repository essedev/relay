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

    /// Monta un overlay a tutta finestra sopra qualunque cosa (dashboard). Uno alla volta: un
    /// overlay nuovo sostituisce il precedente.
    func presentFullOverlay(_ overlayView: NSView) {
        dismissFullOverlay()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView) // ultimo aggiunto = sopra contenuto e toggle sidebar
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        fullOverlay = overlayView
    }

    func dismissFullOverlay() {
        fullOverlay?.removeFromSuperview()
        fullOverlay = nil
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
