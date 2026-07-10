import AppKit
import Core
import SwiftTerm

/// `LocalProcessTerminalView` con due aggiunte: il drop di file (trascinare uno o più file dal
/// Finder inserisce i path escaped nell'input, come Terminal.app/iTerm - SwiftTerm non lo fa da
/// solo) e lo scroll fluido (delta precisi del trackpad invece della quantizzazione a scatti di
/// SwiftTerm, via `SmoothScrollInterceptor`). Resta dentro TerminalEngine: nessun tipo SwiftTerm
/// esce (la surface espone solo `NSView`).
final class RelayTerminalView: LocalProcessTerminalView {
    /// Chiamato al drop con gli URL dei file; la surface costruisce la stringa e la scrive nel PTY.
    var onFilesDropped: (([URL]) -> Void)?

    private var scrollAccumulator = PreciseScrollAccumulator()

    /// Righe per scatto di rotella fisica (senza delta precisi): passo classico dei terminali.
    private static let wheelLinesPerStep: Double = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        SmoothScrollInterceptor.installIfNeeded()
        OptionTextInterceptor.installIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("RelayTerminalView is programmatic-only")
    }

    func handleOptionText(_ event: NSEvent) -> Bool {
        if let text = event.optionGeneratedText {
            process.send(data: ArraySlice(Array(text.utf8)))
            return true
        }
        return false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(from: sender).isEmpty ? [] : .copy
    }

    /// Scroll fluido: SwiftTerm quantizza `event.deltaY` in salti di 1/3/10/20+ righe, ignorando
    /// i delta pixel-precisi del trackpad. Qui il delta preciso si converte in righe (1:1 col
    /// gesto, momentum incluso: macOS continua a mandare eventi in fase di inerzia) e si accumula
    /// il residuo sub-riga. Le righe maturate diventano scroll dello scrollback oppure, con mouse
    /// reporting attivo (es. Claude Code), eventi rotella verso l'app - un evento per riga di
    /// gesto, non la raffica quantizzata. Ritorna `false` (evento non consumato, arriva allo
    /// `scrollWheel` di SwiftTerm) solo per l'alternate buffer senza reporting attivo (frecce
    /// sintetiche, logica interna di SwiftTerm). Shift bypassa il reporting, come in SwiftTerm:
    /// scrolla lo scrollback locale.
    func handleSmoothScroll(_ event: NSEvent) -> Bool {
        let rowHeight = bounds.height / CGFloat(max(terminal.rows, 1))
        guard rowHeight > 0 else { return true }
        let reporting = allowMouseReporting && terminal.mouseMode != .off
            && !event.modifierFlags.contains(.shift)
        if !reporting, terminal.isCurrentBufferAlternate {
            return false
        }
        let deltaInRows = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY / rowHeight
            : event.scrollingDeltaY * Self.wheelLinesPerStep
        let lines = scrollAccumulator.lines(addingDeltaInRows: deltaInRows)
        guard lines != 0 else { return true }
        if reporting {
            sendWheelReports(count: abs(lines), up: lines > 0, event: event)
        } else if lines > 0 {
            scrollUp(lines: lines)
        } else {
            scrollDown(lines: -lines)
        }
        return true
    }

    /// Inoltra `count` eventi rotella SGR all'app nel PTY, alla cella sotto il puntatore.
    /// Equivale al ramo mouse-reporting dello `scrollWheel` di SwiftTerm, ma il numero di eventi
    /// viene dal gesto reale (accumulatore) invece che da `calcScrollingVelocity`.
    private func sendWheelReports(count: Int, up: Bool, event: NSEvent) {
        let flags = event.modifierFlags
        let buttonFlags = terminal.encodeButton(
            button: up ? 4 : 5,
            release: false,
            shift: flags.contains(.shift),
            meta: flags.contains(.option),
            control: flags.contains(.control)
        )
        let point = convert(event.locationInWindow, from: nil)
        let colWidth = bounds.width / CGFloat(max(terminal.cols, 1))
        let rowHeight = bounds.height / CGFloat(max(terminal.rows, 1))
        guard colWidth > 0, rowHeight > 0 else { return }
        // La view non è flipped: la riga 0 è in alto, quindi l'ordinata si inverte.
        let col = min(max(0, Int(point.x / colWidth)), terminal.cols - 1)
        let row = min(max(0, Int((bounds.height - point.y) / rowHeight)), terminal.rows - 1)
        let pixelX = Int(min(max(point.x, 0), bounds.width))
        let pixelY = Int(min(max(bounds.height - point.y, 0), bounds.height))
        for _ in 0 ..< count {
            terminal.sendEvent(
                buttonFlags: buttonFlags,
                x: col,
                y: row,
                pixelX: pixelX,
                pixelY: pixelY
            )
        }
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

private extension NSEvent {
    var optionGeneratedText: String? {
        KeyboardTextInput.optionGeneratedText(
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            modifiers: .init(
                option: modifierFlags.contains(.option),
                shift: modifierFlags.contains(.shift),
                command: modifierFlags.contains(.command),
                control: modifierFlags.contains(.control)
            )
        )
    }
}
