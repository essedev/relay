# Security

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use GitHub's private reporting
(**Security > Report a vulnerability** on this repository), or email
[doppiaesse@proton.me](mailto:doppiaesse@proton.me).

Relay is a single-maintainer side project: expect a first reply within a week. Include what you
did, what happened, and the Relay version (**Relay > About Relay**).

## What Relay touches on your machine

Worth knowing when you assess a report, and when you decide to install it at all.

- **`~/.claude/settings.json`** - `relay-cli hooks setup` appends Relay's hooks to your Claude Code
  settings. Every entry it writes carries `RELAY_MANAGED_HOOK=1`, existing hooks are preserved, a
  backup is taken first and the write is atomic. `relay-cli hooks uninstall` removes only the
  marked entries.
- **`~/.relay/`** - the layout snapshot (`layout.json`) and the Unix domain socket (`relay.sock`)
  the hooks send events to. The socket is local and has no authentication beyond filesystem
  permissions, so any process running as you can write to it. What an event can do is bounded: it
  moves a badge and records a resume id, it never runs a command.
- **`~/.relay/naming-credentials.json`** - the API key for automatic workspace naming, if you set
  one. Written `0600`, kept out of the preferences plist, never logged and never part of an event
  payload. It is used only for requests to the base URL you configured (OpenRouter by default).
- **Network** - two outbound calls, both optional: the update check against the GitHub Releases API
  ("Check for updates on launch" in Settings > Updates, on by default) and workspace naming (off
  until you add a key). Nothing else
  leaves the machine, and there is no telemetry.
- **Terminal sessions** - Relay runs your login shell. It does not read, log or transmit terminal
  output; agent state comes from Claude Code hooks, not from parsing what is on screen.

## Signing

Releases are self-signed, not signed with an Apple Developer ID and not notarized. The Homebrew
cask clears the quarantine attribute after install, so Gatekeeper does not prompt; with a manual
`.dmg` install macOS blocks the first launch until you allow it in System Settings. If that
tradeoff does not work for you, build from source: `make install-app`.
