import Foundation

// CLI di Relay. Output utente su stdout (print qui è corretto: non è logging).
// Comandi reali implementati in Fase 3-4.

let usage = """
relay-cli - Relay command line

Usage:
  relay hooks setup claude
  relay hooks uninstall claude
  relay hooks status
  relay state:claude session-id=... state=... [bypass=0]
"""

let args = Array(CommandLine.arguments.dropFirst())

switch args.first {
case "hooks", "state:claude":
    print("not implemented yet")
default:
    print(usage)
}
