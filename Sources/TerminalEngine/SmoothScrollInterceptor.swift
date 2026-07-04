import AppKit

/// Intercetta gli eventi di scroll destinati a una `RelayTerminalView` prima del dispatch di
/// AppKit e li passa allo scroll fluido della view. Serve un monitor perché
/// `TerminalView.scrollWheel` di SwiftTerm è `public override` (non `open`): la sottoclasse non
/// può ribaltarlo. Un solo monitor per processo, installato pigramente alla prima view; gli
/// eventi fuori dal terminale (o che la view non gestisce, es. mouse reporting attivo) passano
/// intatti al dispatch normale.
@MainActor
enum SmoothScrollInterceptor {
    private static var monitor: Any?

    static func installIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let target = terminalView(under: event) else { return event }
            return target.handleSmoothScroll(event) ? nil : event
        }
    }

    /// La `RelayTerminalView` che riceverebbe l'evento, risalendo dalla view sotto il puntatore.
    private static func terminalView(under event: NSEvent) -> RelayTerminalView? {
        guard let contentView = event.window?.contentView else { return nil }
        var view = contentView.hitTest(event.locationInWindow)
        while let current = view {
            if let terminal = current as? RelayTerminalView { return terminal }
            view = current.superview
        }
        return nil
    }
}
