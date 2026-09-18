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

    /// Controlli per installare/rimuovere gli hook Claude e Codex dalle impostazioni, usando il
    /// `relay-cli` accanto all'eseguibile corrente (nel bundle: `Contents/MacOS/relay-cli`; in dev:
    /// la stessa dir di build). Array vuoto se il cli non è raggiungibile: l'onboarding mostra il
    /// comando manuale e Settings non aggiunge i blocchi.
    func makeHookControls() -> [HookControls] {
        guard let exec = Bundle.main.executableURL else { return [] }
        let cli = exec.deletingLastPathComponent().appendingPathComponent("relay-cli").path
        guard FileManager.default.isExecutableFile(atPath: cli) else { return [] }
        let claude = ClaudeHookInstaller()
        let codex = CodexHookInstaller()
        return [
            HookControls(
                id: "claude",
                title: "Claude Code hooks",
                detail: "Relay reads agent state from Claude Code hooks. Installation appends "
                    + "to ~/.claude/settings.json and keeps existing hooks.",
                isInstalled: { claude.status() },
                install: { try claude.setup(cliPath: cli) },
                uninstall: { try claude.uninstall() }
            ),
            HookControls(
                id: "codex",
                title: "Codex hooks",
                detail: "Relay reads agent state from Codex hooks. Installation appends to "
                    + "~/.codex/hooks.json (or CODEX_HOME/hooks.json) and keeps existing hooks.",
                note: "After installing, open /hooks in Codex to review and trust the user "
                    + "configuration; review again after hook definitions change. "
                    + "Codex hooks do not currently report API failures.",
                isInstalled: { codex.status() },
                install: { try codex.setup(cliPath: cli) },
                uninstall: { try codex.uninstall() }
            ),
        ]
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
