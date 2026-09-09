import Core
import Foundation
import Testing
@testable import WorkspaceModel

// I `UserDefaults` dei test passano tutti da `withTestDefaults` (Fixtures): la suite viene
// cancellata alla fine, altrimenti ogni run lascia un plist in ~/Library/Preferences.

@MainActor @Test func defaultsToRelayDark() {
    withTestDefaults { defaults in
        let settings = AppSettings(defaults: defaults)
        #expect(settings.themeName == "Relay Dark")
        #expect(settings.theme.name == "Relay Dark")
        #expect(settings.availableThemes.count == 12)
    }
}

@MainActor @Test func fontNameDefaultsToSystemAndOverridesTheme() {
    withTestDefaults { defaults in
        let settings = AppSettings(defaults: defaults)
        #expect(settings.fontName == nil)
        #expect(settings.theme.fontName == nil) // monospace di sistema
        settings.setFontName("Menlo")
        #expect(settings.fontName == "Menlo")
        #expect(settings.theme.fontName == "Menlo")
    }
}

@MainActor @Test func fontNameNormalizesEmptyToNil() {
    withTestDefaults { defaults in
        let settings = AppSettings(defaults: defaults)
        settings.setFontName("Menlo")
        settings.setFontName("   ")
        #expect(settings.fontName == nil)
        settings.setFontName("Monaco")
        settings.setFontName(nil)
        #expect(settings.fontName == nil)
        #expect(settings.theme.fontName == nil)
    }
}

@MainActor @Test func fontSizeClampsAndReflectsInTheme() {
    withTestDefaults { defaults in
        let settings = AppSettings(defaults: defaults)
        settings.setFontSize(1000)
        #expect(settings.fontSize == AppSettings.maxFontSize)
        settings.setFontSize(0)
        #expect(settings.fontSize == AppSettings.minFontSize)
        #expect(settings.theme.fontSize == settings.fontSize)
    }
}

@MainActor @Test func selectThemeIgnoresUnknown() {
    withTestDefaults { defaults in
        let settings = AppSettings(defaults: defaults)
        settings.selectTheme("Nope")
        #expect(settings.themeName == "Relay Dark")
        settings.selectTheme("Relay Light")
        #expect(settings.theme.name == "Relay Light")
    }
}

@MainActor @Test func cursorBlinkDefaultsOffAndReflectsInTheme() {
    withTestDefaults { defaults in
        let settings = AppSettings(defaults: defaults)
        #expect(!settings.cursorBlink)
        #expect(!settings.theme.cursorBlink)
        settings.setCursorBlink(true)
        #expect(settings.cursorBlink)
        #expect(settings.theme.cursorBlink)
    }
}

@MainActor @Test func adjustAndReset() {
    withTestDefaults { defaults in
        let settings = AppSettings(defaults: defaults)
        settings.setFontSize(13)
        settings.adjustFontSize(by: 2)
        #expect(settings.fontSize == 15)
        settings.resetFontSize()
        #expect(settings.fontSize == 13)
    }
}

@MainActor @Test func sidebarWidthDefaultsClampsAndPersists() {
    withTestDefaults { defaults in
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
}

@MainActor @Test func newTabOnStripDoubleClickDefaultsOnAndPersists() {
    withTestDefaults { defaults in
        let settings = AppSettings(defaults: defaults)
        #expect(settings.newTabOnStripDoubleClick)
        settings.setNewTabOnStripDoubleClick(false)
        #expect(AppSettings(defaults: defaults).newTabOnStripDoubleClick == false)
    }
}

@MainActor @Test func notificationsDefaultOn() {
    withTestDefaults { defaults in
        let settings = AppSettings(defaults: defaults)
        #expect(settings.notificationsEnabled)
        #expect(settings.notifyOnNeedsInput)
        #expect(settings.notifyOnCompleted)
        #expect(settings.notificationSound)
        #expect(settings.notificationSoundName == "Default")
    }
}

@MainActor @Test func notificationSettingsPersist() {
    withTestDefaults { defaults in
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
}

@MainActor @Test func persistsAcrossInstances() {
    withTestDefaults { defaults in
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
}

// MARK: - Dispatch deterministico delle combo (upgrade dei default)

@MainActor @Test func actionForComboPrefersUserOverrideOverShippedDefault() {
    // Un override salvato in una versione vecchia può collidere con un default nuovo (es. l'utente
    // aveva Clear su ⇧⌘N e poi ⇧⌘N diventa il default di New Window): deve vincere l'override
    // esplicito, non l'azione rimasta sul default, e l'esito non deve dipendere dall'ordine di
    // iterazione di un Dictionary.
    withTestDefaults { defaults in
        let settings = AppSettings(defaults: defaults)
        let combo = ShortcutAction.newWindow.defaultCombo
        settings.setBinding(combo, for: .clear) // l'override dell'utente

        #expect(settings.action(for: combo) == .clear)
        // Le combo senza conflitto risolvono normalmente.
        #expect(settings.action(for: ShortcutAction.newTab.defaultCombo) == .newTab)
        // Una combo ignota non risolve niente.
        #expect(settings.action(for: KeyCombo(key: "9", modifiers: [.control])) == nil)
    }
}

// MARK: - Endpoint della nomina

@MainActor @Test func namingDefaultsToOpenRouter() {
    withTestDefaults { defaults in
        let settings = AppSettings(defaults: defaults)
        #expect(settings.workspaceNamingBaseURL == AppSettings.defaultNamingBaseURL)
        #expect(settings.workspaceNamingBaseURL.contains("openrouter.ai"))
        #expect(settings.workspaceNamingModel == AppSettings.defaultNamingModel)
    }
}

// MARK: - Igiene dei test

/// I `UserDefaults` di un test non devono lasciare niente sul disco: `UserDefaults(suiteName:)`
/// crea un plist vero in `~/Library/Preferences`, e per anni ogni run ne ha lasciato uno per test
/// (se n'erano accumulati oltre tremila). Questo test guarda il file, non l'API: se una versione
/// di macOS sposta il path o cfprefsd ricomincia a rigenerarlo, deve fallire qui.
@MainActor @Test func defaultsLeaveNoFileBehind() {
    var plist: URL?
    withNamedTestDefaults { defaults, name in
        // Una scrittura vera: senza, il plist potrebbe non nascere e il test proverebbe nulla.
        AppSettings(defaults: defaults).setFontSize(17)
        plist = testDefaultsFile(name)
        #expect(FileManager.default.fileExists(atPath: testDefaultsFile(name).path))
    }
    #expect(plist != nil)
    #expect(!FileManager.default.fileExists(atPath: plist?.path ?? ""))
}
