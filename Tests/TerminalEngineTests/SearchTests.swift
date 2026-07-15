import AppKit
import Core
import SwiftTerm
@testable import TerminalEngine
import Testing

// La ricerca (Cmd+F) ha due metà: la navigazione/contatore di SwiftTerm su tutto il buffer, e la
// nostra evidenziazione di tutti i match visibili (mappata alle colonne-cella). Questi test
// pilotano
// il percorso pty vero (`dataReceived`), come i test della selezione: se un bump di SwiftTerm
// cambia
// le regole sotto, diventano rossi invece di degradare in silenzio.

@MainActor
private func makeView(lines: String...) -> RelayTerminalView {
    let view = RelayTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    for line in lines {
        view.receive(line + "\r\n")
    }
    return view
}

private extension RelayTerminalView {
    func receive(_ text: String) {
        dataReceived(slice: ArraySlice(Array(text.utf8)))
    }

    func segments(
        _ term: String,
        options: TerminalSearchOptions = TerminalSearchOptions()
    ) -> [RelayTerminalView.MatchSegment] {
        let terminal = getTerminal()
        return RelayTerminalView.visibleMatchSegments(
            reader: { terminal.getLine(row: $0) },
            rows: terminal.rows,
            cols: terminal.cols,
            term: term,
            options: options
        )
    }
}

// MARK: - Contatore / navigazione (motore SwiftTerm)

@MainActor
@Test func counterCountsMatchesAcrossTheBuffer() {
    let view = makeView(lines: "alpha beta", "beta gamma", "delta beta")
    view.findNext("beta")
    let summary = view.searchMatchSummary("beta")
    #expect(summary.total == 3)
    #expect(summary.index >= 1)
}

@MainActor
@Test func navigationWrapsAround() {
    let view = makeView(lines: "match", "nope", "match")
    view.findNext("match")
    let first = view.searchMatchSummary("match").index
    view.findNext("match")
    view.findNext("match") // oltre l'ultimo: torna al primo
    let wrapped = view.searchMatchSummary("match").index
    #expect(first == wrapped)
}

// MARK: - Evidenziazione (mapping colonne-cella)

@MainActor
@Test func highlightSegmentsMapVisibleMatchColumns() {
    let view = makeView(lines: "foo bar foo")
    let segments = view.segments("foo")
    #expect(segments.count == 2)
    #expect(segments.contains(.init(screenRow: 0, col: 0, cells: 3)))
    #expect(segments.contains(.init(screenRow: 0, col: 8, cells: 3)))
}

@MainActor
@Test func highlightRespectsCaseSensitivity() {
    let view = makeView(lines: "Foo foo FOO")
    #expect(view.segments("foo").count == 3)
    #expect(view.segments("foo", options: TerminalSearchOptions(caseSensitive: true)).count == 1)
}

@MainActor
@Test func highlightWholeWordExcludesSubstrings() {
    let view = makeView(lines: "cat category cat")
    let all = view.segments("cat")
    #expect(all.count == 3)
    let whole = view.segments("cat", options: TerminalSearchOptions(wholeWord: true))
    #expect(whole.count == 2)
}

@MainActor
@Test func highlightWideCharacterSpansTwoCells() {
    // Una CJK (larga due celle) prima del termine sposta la colonna di due, non di uno.
    let view = makeView(lines: "世 foo")
    let segments = view.segments("foo")
    #expect(segments.count == 1)
    // "世" occupa le colonne 0-1, lo spazio la 2, "foo" parte dalla colonna 3.
    #expect(segments.first == .init(screenRow: 0, col: 3, cells: 3))
}

@MainActor
@Test func emptyTermHasNoSegments() {
    let view = makeView(lines: "anything")
    #expect(view.segments("").isEmpty)
}

// MARK: - Scrollback esteso

@MainActor
@Test func extendedScrollbackKeepsHistorySearchable() {
    let view = makeView()
    // Come fa `SwiftTermSurface.start`: alza lo scrollback dal default (500) a 10k.
    view.getTerminal().buffer.changeHistorySize(10000)
    for index in 0 ..< 700 {
        view.receive("line \(index)\r\n")
    }
    #expect(view.getTerminal().buffer.totalLinesTrimmed == 0,
            "con scrollback esteso 700 righe non devono trimmare (col default 500 sì)")
    // La riga più vecchia è ancora nel buffer, quindi ricercabile.
    view.findNext("line 0")
    #expect(view.searchMatchSummary("line 0").total >= 1)
}

// MARK: - Robustezza durante lo streaming

@MainActor
@Test func searchSelectionSurvivesStreamingWithMouseTrackingOn() {
    let view = makeView(lines: "target here", "second line")
    view.setSearchState(term: "target", options: TerminalSearchOptions())
    view.findNext("target")
    #expect(view.selectionActive, "il match deve essere selezionato")

    // App con mouse tracking attivo (es. Claude Code) + output che riscrive la sua riga.
    view.receive("\u{1b}[?1000h")
    for index in 0 ..< 20 {
        view.receive("\rstreaming \(index)")
    }
    #expect(view.selectionActive,
            "con ricerca attiva la selezione del match deve sopravvivere all'output in streaming")

    view.clearSearchState()
    #expect(!view.isSearchActive)
}
