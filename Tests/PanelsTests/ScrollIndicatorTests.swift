import CoreGraphics
@testable import Panels
import Testing

// Geometria della barretta di scroll: proporzione, estremi, rimbalzo elastico.

private func knob(
    offset: CGFloat, content: CGFloat = 1000, viewport: CGFloat = 200
) -> ScrollIndicatorKnob? {
    ScrollIndicatorKnob(
        offset: offset, content: content, viewport: viewport, inset: 2, minLength: 24
    )
}

private func near(_ a: CGFloat?, _ b: CGFloat) -> Bool {
    a.map { abs($0 - b) < 0.0001 } ?? false
}

@Test func contentThatFitsHasNoKnob() {
    #expect(knob(offset: 0, content: 200) == nil)
    #expect(knob(offset: 0, content: 150) == nil)
}

@Test func knobLengthIsProportionalToTheVisibleShare() {
    // Track 196, viewport 1/5 del contenuto.
    #expect(near(knob(offset: 0)?.length, 196 / 5))
}

@Test func knobSpansTheTrackFromTopToBottom() {
    #expect(knob(offset: 0)?.top == 2)
    let bottom = knob(offset: 800)
    #expect(near(bottom.map { $0.top + $0.length }, 198))
}

@Test func veryLongContentKeepsTheMinimumLength() {
    #expect(knob(offset: 0, content: 100_000)?.length == 24)
}

@Test func overscrollShortensTheKnobInsteadOfLeavingTheTrack() throws {
    let rest = try #require(knob(offset: 0))
    let pulled = try #require(knob(offset: -20))
    #expect(pulled.top == 2)
    #expect(near(pulled.length, rest.length - 20))
    let pushed = try #require(knob(offset: 815))
    #expect(near(pushed.length, rest.length - 15))
    #expect(near(pushed.top + pushed.length, 198))
}

@Test func overscrollNeverCollapsesTheKnob() {
    #expect(knob(offset: -500)?.length == 12)
}
