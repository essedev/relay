import AppKit
import TerminalEngine

/// Host AppKit della terminal surface: è sul path caldo (latenza input), quindi AppKit puro.
/// Stub: NSView vuota. In Fase 2 ospita la view della `TerminalEngine` (SwiftTerm).
public final class TerminalHostView: NSView {
    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("TerminalHostView is programmatic-only")
    }
}
