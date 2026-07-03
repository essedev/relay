import Core
import Foundation
import Testing
@testable import WorkspaceModel

private func freshDefaults() -> UserDefaults {
    let name = "relay-test-\(UInt64.random(in: 0 ..< 1_000_000_000))"
    guard let defaults = UserDefaults(suiteName: name) else { return .standard }
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor @Test func defaultsToRelayDark() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(settings.themeName == "Relay Dark")
    #expect(settings.theme.name == "Relay Dark")
    #expect(settings.availableThemes.count == 12)
}

@MainActor @Test func fontNameDefaultsToSystemAndOverridesTheme() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(settings.fontName == nil)
    #expect(settings.theme.fontName == nil) // monospace di sistema
    settings.setFontName("Menlo")
    #expect(settings.fontName == "Menlo")
    #expect(settings.theme.fontName == "Menlo")
}

@MainActor @Test func fontNameNormalizesEmptyToNil() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.setFontName("Menlo")
    settings.setFontName("   ")
    #expect(settings.fontName == nil)
    settings.setFontName("Monaco")
    settings.setFontName(nil)
    #expect(settings.fontName == nil)
    #expect(settings.theme.fontName == nil)
}

@MainActor @Test func fontSizeClampsAndReflectsInTheme() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.setFontSize(1000)
    #expect(settings.fontSize == AppSettings.maxFontSize)
    settings.setFontSize(0)
    #expect(settings.fontSize == AppSettings.minFontSize)
    #expect(settings.theme.fontSize == settings.fontSize)
}

@MainActor @Test func selectThemeIgnoresUnknown() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.selectTheme("Nope")
    #expect(settings.themeName == "Relay Dark")
    settings.selectTheme("Relay Light")
    #expect(settings.theme.name == "Relay Light")
}

@MainActor @Test func cursorBlinkDefaultsOffAndReflectsInTheme() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(!settings.cursorBlink)
    #expect(!settings.theme.cursorBlink)
    settings.setCursorBlink(true)
    #expect(settings.cursorBlink)
    #expect(settings.theme.cursorBlink)
}

@MainActor @Test func adjustAndReset() {
    let settings = AppSettings(defaults: freshDefaults())
    settings.setFontSize(13)
    settings.adjustFontSize(by: 2)
    #expect(settings.fontSize == 15)
    settings.resetFontSize()
    #expect(settings.fontSize == 13)
}

@MainActor @Test func sidebarWidthDefaultsClampsAndPersists() {
    let defaults = freshDefaults()
    let first = AppSettings(defaults: defaults)
    #expect(first.sidebarWidth == AppSettings.defaultSidebarWidth)
    first.setSidebarWidth(500)
    #expect(first.sidebarWidth == AppSettings.maxSidebarWidth)
    first.setSidebarWidth(0)
    #expect(first.sidebarWidth == AppSettings.minSidebarWidth)
    first.setSidebarWidth(280)

    let second = AppSettings(defaults: defaults)
    #expect(second.sidebarWidth == 280)
}

@MainActor @Test func notificationsDefaultOn() {
    let settings = AppSettings(defaults: freshDefaults())
    #expect(settings.notificationsEnabled)
    #expect(settings.notifyOnNeedsInput)
    #expect(settings.notifyOnCompleted)
    #expect(settings.notificationSound)
    #expect(settings.notificationSoundName == "Default")
}

@MainActor @Test func notificationSettingsPersist() {
    let defaults = freshDefaults()
    let first = AppSettings(defaults: defaults)
    first.setNotificationsEnabled(false)
    first.setNotifyOnCompleted(false)
    first.setNotificationSound(false)
    first.setNotificationSoundName("Glass")

    let second = AppSettings(defaults: defaults)
    #expect(!second.notificationsEnabled)
    #expect(second.notifyOnNeedsInput) // non toccato: resta true
    #expect(!second.notifyOnCompleted)
    #expect(!second.notificationSound)
    #expect(second.notificationSoundName == "Glass")
}

@MainActor @Test func persistsAcrossInstances() {
    let defaults = freshDefaults()
    let first = AppSettings(defaults: defaults)
    first.selectTheme("Relay Light")
    first.setFontSize(18)
    first.setCursorBlink(true)
    first.setFontName("Menlo")

    let second = AppSettings(defaults: defaults)
    #expect(second.themeName == "Relay Light")
    #expect(second.fontSize == 18)
    #expect(second.cursorBlink)
    #expect(second.fontName == "Menlo")
}
