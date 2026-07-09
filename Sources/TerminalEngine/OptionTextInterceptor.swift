import AppKit

@MainActor
enum OptionTextInterceptor {
    private static var monitor: Any?

    static func installIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let target = terminalView(focusedIn: event.window ?? NSApp.keyWindow) else {
                return event
            }
            return target.handleOptionText(event) ? nil : event
        }
    }

    private static func terminalView(focusedIn window: NSWindow?) -> RelayTerminalView? {
        var responder = window?.firstResponder
        while let current = responder {
            if let terminal = terminalView(from: current) { return terminal }
            responder = current.nextResponder
        }
        return nil
    }

    private static func terminalView(from responder: NSResponder) -> RelayTerminalView? {
        if let terminal = responder as? RelayTerminalView { return terminal }
        guard let view = responder as? NSView else { return nil }
        var current: NSView? = view
        while let view = current {
            if let terminal = view as? RelayTerminalView { return terminal }
            current = view.superview
        }
        return nil
    }
}
