import AppKit
import Core
import SwiftTerm

/// Evidenziazione della ricerca (Cmd+F). SwiftTerm sa navigare i match e contarli su tutto il
/// buffer (`findNext`/`searchMatchSummary`), ma **non** espone le posizioni di tutti i match,
/// quindi
/// non li può evidenziare. Qui si disegna, sopra la sola **viewport**, un rettangolo per ogni
/// occorrenza visibile: il navigatore SwiftTerm resta la sorgente autorevole di contatore e match
/// corrente (quest'ultimo dato dalla selezione nativa, colore selezione del tema, sotto l'overlay);
/// l'overlay è l'aiuto visivo "gli altri match sono qui".
///
/// L'evidenziazione è una **subview** (non un override di `draw`: SwiftTerm dichiara `draw` come
/// `public`, non `open`, quindi non è overridabile da qui - stesso motivo per cui il ring di
/// attenzione è una view a parte). La geometria segue il `draw` di SwiftTerm su macOS: la view non
/// è
/// flipped, le righe sono ancorate a `bounds.maxY` e alte `cellDimension.height`. La dimensione
/// cella
/// esatta viene da `caretFrame.size` (il caret è grande una cella), non da `cellSizeInPixels`
/// (arrotondato ai pixel, accumulerebbe errore lungo la riga).
extension RelayTerminalView {
    /// Un tratto di match su una singola riga a schermo, in colonne-cella.
    struct MatchSegment: Equatable {
        let screenRow: Int
        let col: Int
        let cells: Int
    }

    var isSearchActive: Bool {
        !searchState.term.isEmpty
    }

    /// Imposta termine e opzioni per l'evidenziazione, installa l'overlay se serve e lo aggiorna.
    /// Chiamato dal motore di ricerca della surface a ogni digitazione/navigazione.
    func setSearchState(term: String, options: TerminalSearchOptions) {
        searchState = (term, options)
        // Spegne il mouse reporting subito (non solo al prossimo feed), così la selezione del match
        // sopravvive anche se l'output arriva prima del redraw (vedi `dataReceived`).
        allowMouseReporting = false
        installSearchOverlayIfNeeded()
        refreshSearchOverlay()
    }

    /// Azzera l'evidenziazione (chiusura della find bar o query svuotata), rimuove l'overlay e
    /// ripristina il mouse reporting reale.
    func clearSearchState() {
        guard isSearchActive || searchOverlay != nil else { return }
        searchState = ("", TerminalSearchOptions())
        allowMouseReporting = getTerminal().mouseMode != .off
        searchOverlay?.removeFromSuperview()
        searchOverlay = nil
    }

    /// Ricalcola i match visibili e li passa all'overlay. Chiamato su digitazione, output (feed),
    /// scroll e resize; no-op a ricerca non attiva.
    func refreshSearchOverlay() {
        guard isSearchActive, let overlay = searchOverlay else { return }
        let terminal = getTerminal()
        overlay.frame = bounds
        overlay.cell = caretFrame.size
        overlay.color = searchHighlightColor
        overlay.segments = Self.visibleMatchSegments(
            reader: { row in terminal.getLine(row: row) },
            rows: terminal.rows,
            cols: terminal.cols,
            term: searchState.term,
            options: searchState.options
        )
        overlay.needsDisplay = true
    }

    private func installSearchOverlayIfNeeded() {
        guard searchOverlay == nil else { return }
        let overlay = SearchHighlightOverlay(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay, positioned: .above, relativeTo: nil)
        searchOverlay = overlay
    }

    // MARK: - Calcolo dei segmenti (puro, testabile via reader iniettato)

    /// Calcola i tratti di match visibili leggendo le righe della viewport tramite `reader`. Cerca
    /// **una riga fisica alla volta** e rimappa gli indici di carattere alle colonne-cella
    /// (gestendo
    /// le celle wide, larghe due). SwiftTerm non espone pubblicamente `isWrapped`, quindi non si
    /// possono unire le righe di un a-capo automatico in una riga logica: un match che cade
    /// esattamente sul bordo di wrap non viene evidenziato (il contatore/navigazione di SwiftTerm,
    /// che accede al wrap internamente, restano comunque autorevoli su tutto il buffer). Cercare
    /// per
    /// riga fisica evita i falsi positivi che nascerebbero concatenando righe separate da un vero
    /// newline.
    static func visibleMatchSegments(
        reader: (Int) -> BufferLine?,
        rows: Int,
        cols: Int,
        term: String,
        options: TerminalSearchOptions
    ) -> [MatchSegment] {
        guard !term.isEmpty, rows > 0, cols > 0 else { return [] }
        var segments: [MatchSegment] = []
        for screenRow in 0 ..< rows {
            guard let line = reader(screenRow) else { break }
            var text: [Character] = []
            var columns: [(col: Int, cells: Int)] = []
            let limit = min(line.getTrimmedLength(), cols)
            var col = 0
            while col < limit {
                let width = max(line.getWidth(index: col), 1)
                let character = line[col].getCharacter()
                text.append(character == "\0" ? " " : character)
                columns.append((col, width))
                col += width
            }
            guard !text.isEmpty else { continue }
            for range in TerminalSearchMatcher.matches(
                in: String(text),
                term: term,
                options: options
            ) {
                guard range.lowerBound < columns.count else { continue }
                let upper = min(range.upperBound, columns.count)
                let startCol = columns[range.lowerBound].col
                let cells = columns[range.lowerBound ..< upper].reduce(0) { $0 + $1.cells }
                segments.append(MatchSegment(screenRow: screenRow, col: startCol, cells: cells))
            }
        }
        return segments
    }
}

/// La subview trasparente agli eventi che disegna i rettangoli di evidenziazione. Non flipped come
/// il terminale: le righe si ancorano a `bounds.maxY`.
final class SearchHighlightOverlay: NSView {
    var segments: [RelayTerminalView.MatchSegment] = []
    var cell: CGSize = .zero
    var color: NSColor = .systemYellow

    override var isFlipped: Bool {
        false
    }

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        false
    }

    override func draw(_: NSRect) {
        guard cell.width > 0, cell.height > 0, !segments.isEmpty else { return }
        color.setFill()
        let maxY = bounds.maxY
        for segment in segments {
            NSRect(
                x: CGFloat(segment.col) * cell.width,
                y: maxY - CGFloat(segment.screenRow + 1) * cell.height,
                width: CGFloat(segment.cells) * cell.width,
                height: cell.height
            ).fill(using: .sourceOver)
        }
    }
}
