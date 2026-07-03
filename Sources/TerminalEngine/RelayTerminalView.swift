import AppKit
import SwiftTerm

/// `LocalProcessTerminalView` col drop di file: trascinare uno o più file dal Finder inserisce i
/// loro path (escaped) nell'input, come Terminal.app/iTerm. SwiftTerm non lo fa da solo. Resta
/// dentro TerminalEngine: nessun tipo SwiftTerm esce (la surface espone solo `NSView`).
final class RelayTerminalView: LocalProcessTerminalView {
    /// Chiamato al drop con gli URL dei file; la surface costruisce la stringa e la scrive nel PTY.
    var onFilesDropped: (([URL]) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("RelayTerminalView is programmatic-only")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
    }

    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        )
        return objects as? [URL] ?? []
    }
}
