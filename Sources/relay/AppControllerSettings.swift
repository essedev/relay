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
        let panel = makePanelWindow(
            title: "Settings",
            size: NSSize(width: 580, height: 400),
            theme: settings.theme,
            content: SettingsView(
                settings: settings,
                hooks: makeHookControls(),
                naming: makeNamingControls()
            )
        )
        settingsWindow = panel
        panel.makeKeyAndOrderFront(nil)
    }

    /// Pannello "About Relay": look ispirato ad "About This Mac", stessa meccanica di finestra di
    /// `openSettings` (riuso se già aperto). La versione viene dal bundle (Info.plist, iniettata da
    /// `./VERSION` al `make bundle`); da `swift run` non c'è Info.plist, quindi "dev".
    @objc func showAbout(_: Any?) {
        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            return
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let panel = makePanelWindow(
            title: "",
            size: NSSize(width: 320, height: 300),
            theme: settings.theme,
            content: AboutView(settings: settings, version: version)
        )
        panel.titleVisibility = .hidden
        aboutWindow = panel
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

    /// Controlli per la API key della nomina automatica: legge/salva la chiave dal
    /// `NamingCredentialStore` (file 0600) e ri-valuta il controller dopo un cambio
    /// (chiave/toggle),
    /// perché la presenza della chiave non è osservabile.
    func makeNamingControls() -> NamingControls {
        NamingControls(
            hasKey: { [weak self] in self?.namingCredentials.hasKey() ?? false },
            saveKey: { [weak self] key in self?.namingCredentials.saveKey(key) },
            onConfigChange: { [weak self] in self?.reconfigureWorkspaceNaming() }
        )
    }
}
