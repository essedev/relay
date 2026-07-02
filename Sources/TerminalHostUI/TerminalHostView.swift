import AppKit
import TerminalEngine

/// Host AppKit della terminal surface: è sul path caldo (latenza input), quindi AppKit puro.
/// Embedda la view di una `TerminalSurfaceHandle` e la tiene ancorata ai bordi.
@MainActor
public final class TerminalHostView: NSView {
    private let surface: TerminalSurfaceHandle

    public init(surface: TerminalSurfaceHandle) {
        self.surface = surface
        super.init(frame: .zero)

        let content = surface.view
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("TerminalHostView is programmatic-only")
    }

    /// Avvia la surface (lazy). Da chiamare quando il pane diventa visibile/focalizzato.
    public func start() {
        surface.start()
    }

    /// La view interna che deve prendere il first responder per l'input tastiera.
    public var focusView: NSView {
        surface.view
    }
}
