@testable import Core
import Testing

private func ranges(
    _ text: String,
    _ term: String,
    caseSensitive: Bool = false,
    wholeWord: Bool = false,
    regex: Bool = false
) -> [Range<Int>] {
    TerminalSearchMatcher.matches(
        in: text,
        term: term,
        options: TerminalSearchOptions(
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            regex: regex
        )
    )
}

@Test func findsAllOccurrences() {
    #expect(ranges("aba aba", "a") == [0 ..< 1, 2 ..< 3, 4 ..< 5, 6 ..< 7])
}

@Test func nonOverlappingMatches() {
    // "aa" in "aaaa" -> due match, non tre sovrapposti.
    #expect(ranges("aaaa", "aa") == [0 ..< 2, 2 ..< 4])
}

@Test func caseInsensitiveByDefault() {
    #expect(ranges("Error error ERROR", "error") == [0 ..< 5, 6 ..< 11, 12 ..< 17])
}

@Test func caseSensitiveWhenRequested() {
    #expect(ranges("Error error ERROR", "error", caseSensitive: true) == [6 ..< 11])
}

@Test func wholeWordExcludesSubstrings() {
    // "cat" whole-word: solo la parola isolata, non "category" né "scatter".
    let text = "cat category scatter cat."
    let result = ranges(text, "cat", wholeWord: true)
    #expect(result == [0 ..< 3, 21 ..< 24])
}

@Test func emptyTermOrTextYieldsNothing() {
    #expect(ranges("hello", "").isEmpty)
    #expect(ranges("", "x").isEmpty)
}

@Test func termLongerThanTextYieldsNothing() {
    #expect(ranges("hi", "hello").isEmpty)
}

@Test func unicodeCharacterIndicesNotUTF16() {
    // Una emoji è un singolo Character: "world" inizia all'indice 2, non spostato dai code unit.
    let text = "👋🏽 world"
    #expect(ranges(text, "world") == [2 ..< 7])
}

@Test func regexMatches() {
    let text = "err 42 warn 7 err 100"
    #expect(ranges(text, "[0-9]+", regex: true) == [4 ..< 6, 12 ..< 13, 18 ..< 21])
}

@Test func regexCaseInsensitiveByDefault() {
    #expect(ranges("FOO foo", "foo", regex: true) == [0 ..< 3, 4 ..< 7])
}

@Test func invalidRegexYieldsNothing() {
    #expect(ranges("abc", "[unterminated", regex: true).isEmpty)
}

@Test func regexZeroWidthMatchesAreSkipped() {
    // `a*` produce match a larghezza zero: non devono comparire né mandare in loop.
    #expect(ranges("bbb", "a*", regex: true).isEmpty)
}
