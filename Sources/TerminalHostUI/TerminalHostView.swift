import AppKit
import TerminalEngine

/// Host AppKit della terminal surface: è sul path caldo (latenza input), quindi AppKit puro.
/// Stub: NSView vuota. In Fase 2 ospita la view della `TerminalEngine` (SwiftTerm).
public final class TerminalHostView: NSView {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("TerminalHostView is programmatic-only")
    }
}
