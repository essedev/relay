@testable import Core
import Testing

@Test func parsesFileURLWithHost() {
    #expect(OSC7.path(from: "file://Mac.local/Users/doppia/dev") == "/Users/doppia/dev")
}

@Test func parsesPercentEncodedPath() {
    #expect(OSC7.path(from: "file://host/Users/doppia/my%20dir") == "/Users/doppia/my dir")
}

@Test func acceptsPlainAbsolutePath() {
    #expect(OSC7.path(from: "/Users/doppia") == "/Users/doppia")
}

@Test func rejectsNonFileSchemes() {
    #expect(OSC7.path(from: "https://example.com/x") == nil)
    #expect(OSC7.path(from: "garbage") == nil)
}
