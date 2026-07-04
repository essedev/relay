import AppKit
import HookInstaller
import Panels
import SwiftUI

/// Wiring del pannello impostazioni, estratto dal corpo di `AppController` per tenerlo sul solo
/// bootstrap: apertura della finestra e costruzione dei controlli hook di Claude.
extension AppController {
    @objc func openSettings(_: Any?) {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(
            rootView: SettingsView(settings: settings, hooks: makeHookControls())
        )
        hosting.preferredContentSize = NSSize(width: 580, height: 400)
        let panel = NSWindow(contentViewController: hosting)
        panel.title = "Settings"
        panel.styleMask = [.titled, .closable]
        panel.isReleasedWhenClosed = false
        panel.center()
        settingsWindow = panel
        applyWindowChrome(settings.theme) // appearance/background coerenti da subito
        panel.makeKeyAndOrderFront(nil)
    }

    /// Controlli per installare/rimuovere gli hook di Claude dalle impostazioni, usando il
    /// `relay-cli` accanto all'eseguibile corrente (nel bundle: `Contents/MacOS/relay-cli`; in dev:
    /// la stessa dir di build). `nil` se il cli non è raggiungibile, così il blocco resta nascosto.
    func makeHookControls() -> HookControls? {
        guard let exec = Bundle.main.executableURL else { return nil }
        let cli = exec.deletingLastPathComponent().appendingPathComponent("relay-cli").path
        guard FileManager.default.isExecutableFile(atPath: cli) else { return nil }
        let installer = ClaudeHookInstaller()
        return HookControls(
            isInstalled: { installer.status() },
            install: { try installer.setup(cliPath: cli) },
            uninstall: { try installer.uninstall() }
        )
    }
}
