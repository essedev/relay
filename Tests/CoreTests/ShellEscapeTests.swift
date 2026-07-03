@testable import Core
import Testing

@Test func simplePathIsUnchanged() {
    #expect(ShellEscape.path("/Users/doppia/dev/file.txt") == "/Users/doppia/dev/file.txt")
}

@Test func spacesAreBackslashEscaped() {
    #expect(ShellEscape.path("/Users/doppia/My Project/a b.txt")
        == "/Users/doppia/My\\ Project/a\\ b.txt")
}

@Test func shellMetacharactersAreEscaped() {
    #expect(ShellEscape.path("/tmp/(x)&'y'.txt") == "/tmp/\\(x\\)\\&\\'y\\'.txt")
}

@Test func joinedAddsTrailingSpaceAndSeparators() {
    let result = ShellEscape.joined(["/a/b.txt", "/c d/e.txt"])
    #expect(result == "/a/b.txt /c\\ d/e.txt ")
}

@Test func joinedEmptyIsEmpty() {
    #expect(ShellEscape.joined([]) == "")
}
