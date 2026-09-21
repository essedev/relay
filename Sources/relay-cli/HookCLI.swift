import Foundation
import HookInstaller

/// Sottocomandi `relay-cli hooks setup|uninstall|status [claude|codex|all]`.
enum HookCLI {
    private enum Target: String {
        case claude, codex, all
    }

    static func run(_ args: [String], cliPath: String) -> Int32 {
        guard let action = args.first else {
            printUsage()
            return 0
        }
        guard let target = Target(rawValue: args.dropFirst().first ?? "claude"), args.count <= 2
        else {
            FileHandle.standardError.write(Data("relay-cli hooks: invalid agent\n".utf8))
            printUsage()
            return 1
        }

        switch action {
        case "setup": return setup(target, cliPath: cliPath)
        case "uninstall": return uninstall(target)
        case "status": return status(target)
        default:
            FileHandle.standardError.write(
                Data("relay-cli hooks: unknown subcommand '\(action)'\n".utf8)
            )
            printUsage()
            return 1
        }
    }

    private static func setup(_ target: Target, cliPath: String) -> Int32 {
        do {
            if target == .claude || target == .all {
                try ClaudeHookInstaller().setup(cliPath: cliPath)
                print("Claude hooks installed in \(ClaudeHookInstaller.defaultSettingsPath)")
            }
            if target == .codex || target == .all {
                try CodexHookInstaller().setup(cliPath: cliPath)
                print("Codex hooks installed in \(CodexHookInstaller.defaultSettingsPath)")
                print("Open /hooks in Codex to review and trust the user hook configuration.")
            }
            return 0
        } catch {
            print("hook setup failed: \(error)")
            return 1
        }
    }

    private static func uninstall(_ target: Target) -> Int32 {
        do {
            if target == .claude || target == .all {
                try ClaudeHookInstaller().uninstall()
                print("Claude hooks removed from \(ClaudeHookInstaller.defaultSettingsPath)")
            }
            if target == .codex || target == .all {
                try CodexHookInstaller().uninstall()
                print("Codex hooks removed from \(CodexHookInstaller.defaultSettingsPath)")
            }
            return 0
        } catch {
            print("hook uninstall failed: \(error)")
            return 1
        }
    }

    private static func status(_ target: Target) -> Int32 {
        if target == .claude || target == .all {
            print("Claude hooks: \(describe(ClaudeHookInstaller().state()))")
        }
        if target == .codex || target == .all {
            print("Codex hooks: \(describe(CodexHookInstaller().state()))")
        }
        return 0
    }

    /// Un booleano non bastava: "not installed" su una configurazione che funziona per sei hook
    /// su otto non dice quale pezzo manca, e il pezzo mancante era l'unica sorgente dello stato
    /// `error`.
    private static func describe(_ state: RelayHookState) -> String {
        switch state {
        case .installed:
            "installed"
        case .absent:
            "not installed"
        case let .drifted(missing):
            "out of date, missing \(missing.joined(separator: ", ")) "
                + "(run: relay-cli hooks setup)"
        }
    }

    private static func printUsage() {
        print("usage: relay-cli hooks setup|uninstall|status [claude|codex|all]")
    }
}
