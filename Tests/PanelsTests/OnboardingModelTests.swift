@testable import Panels
import Testing

// Navigazione dell'onboarding: ordine delle pagine, clamp ai bordi, selezione diretta dai dot.

@Test func pagesAreInPresentationOrder() {
    #expect(OnboardingPage.allCases == [.welcome, .hooks, .attention, .navigation, .customize])
}

@Test func startsAtWelcome() {
    let model = OnboardingModel()
    #expect(model.page == .welcome)
    #expect(model.isFirst)
    #expect(!model.isLast)
}

@Test func advanceWalksAllPagesAndClampsAtLast() {
    var model = OnboardingModel()
    var visited: [OnboardingPage] = [model.page]
    for _ in 1 ..< OnboardingPage.allCases.count {
        model.advance()
        visited.append(model.page)
    }
    #expect(visited == OnboardingPage.allCases)
    #expect(model.isLast)
    model.advance() // oltre l'ultima: resta ferma, niente wrap
    #expect(model.page == OnboardingPage.allCases.last)
}

@Test func backClampsAtFirst() {
    var model = OnboardingModel()
    model.back()
    #expect(model.page == .welcome)
    model.advance()
    model.back()
    #expect(model.page == .welcome)
}

@Test func selectJumpsToAnyPage() {
    var model = OnboardingModel()
    model.select(.navigation)
    #expect(model.page == .navigation)
    #expect(!model.isFirst)
    model.select(.welcome)
    #expect(model.isFirst)
}
