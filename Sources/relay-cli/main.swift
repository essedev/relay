import Foundation
import HookInstaller

// CLI di Relay. Output utente su stdout (print qui è corretto: non è logging).

let usage = """
relay-cli - Relay command line

Usage:
  relay-cli hooks setup           install Claude hooks in ~/.claude/settings.json
  relay-cli hooks uninstall       remove Relay-managed hooks
  relay-cli hooks status          report whether Relay hooks are installed
  relay-cli claude-hook <state>   (invoked by hooks) emit an agent state event

States: running | idle | needs_input | error | unknown
"""

let arguments = Array(CommandLine.arguments.dropFirst())

/// Path assoluto di questo eseguibile: finisce nei comandi hook di settings.json.
func cliExecutablePath() -> String {
    Bundle.main.executablePath ?? CommandLine.arguments.first ?? "relay-cli"
}

switch arguments.first {
case "claude-hook":
    exit(ClaudeHookCommand.run(stateArg: arguments.count > 1 ? arguments[1] : nil))
case "hooks":
    exit(HookCLI.run(Array(arguments.dropFirst()), cliPath: cliExecutablePath()))
default:
    print(usage)
}
