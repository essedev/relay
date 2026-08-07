import Foundation

/// Le chiavi UserDefaults delle preferenze, in un file loro: `AppSettings` era oltre il budget di
/// dimensione (400 righe) e questo è il pezzo che non ha niente a che vedere col comportamento -
/// solo nomi. `internal` invece che `private` perché ora vive fuori dal file del tipo; a scriverci
/// restano i soli setter.
extension AppSettings {
    enum Keys {
        static let themeName = "relay.theme.name"
        static let fontSize = "relay.theme.fontSize"
        static let fontName = "relay.theme.fontName"
        static let cursorBlink = "relay.cursor.blink"
        static let sidebarCollapsed = "relay.sidebar.collapsed"
        static let archiveExpanded = "relay.sidebar.archiveExpanded"
        static let sidebarWidth = "relay.sidebar.width"
        static let autoResumeAgents = "relay.agents.autoResume"
        static let pendingDecayHours = "relay.agents.pendingDecayHours"
        static let notificationsEnabled = "relay.notifications.enabled"
        static let notifyOnNeedsInput = "relay.notifications.needsInput"
        static let notifyOnCompleted = "relay.notifications.completed"
        static let notificationSound = "relay.notifications.sound"
        static let notificationSoundName = "relay.notifications.soundName"
        static let checkForUpdates = "relay.updates.checkAutomatically"
        static let skippedUpdateVersion = "relay.updates.skippedVersion"
        static let onboardingSeen = "relay.onboarding.seen"
        static let dashboardLayout = "relay.dashboard.layout"
        static let workspaceNamingEnabled = "relay.naming.enabled"
        static let workspaceNamingBaseURL = "relay.naming.baseURL"
        static let workspaceNamingModel = "relay.naming.model"
        static let keybindings = "relay.shortcuts.bindings"
    }
}
