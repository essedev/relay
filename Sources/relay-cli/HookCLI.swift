import Foundation
import HookInstaller

/// Sottocomandi `relay-cli hooks setup|uninstall|status`. Output utente su stdout.
enum HookCLI {
    static func run(_ args: [String], cliPath: String) -> Int32 {
        let installer = ClaudeHookInstaller()
        let settingsPath = ClaudeHookInstaller.defaultSettingsPath

        switch args.first {
        case "setup":
            do {
                try installer.setup(cliPath: cliPath)
                print("Relay hooks installed in \(settingsPath)")
                return 0
            } catch {
                print("hook setup failed: \(error)")
                return 1
            }

        case "uninstall":
            do {
                try installer.uninstall()
                print("Relay hooks removed from \(settingsPath)")
                return 0
            } catch {
                print("hook uninstall failed: \(error)")
                return 1
            }

        case "status":
            print(installer.status() ? "Relay hooks: installed" : "Relay hooks: not installed")
            return 0

        case nil:
            print("usage: relay-cli hooks setup|uninstall|status")
            return 0

        default:
            let message = "relay-cli hooks: unknown subcommand '\(args[0])'\n"
            FileHandle.standardError.write(Data(message.utf8))
            print("usage: relay-cli hooks setup|uninstall|status")
            return 1
        }
    }
}
