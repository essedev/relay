<div align="center">

<img src="docs/images/relay-icon.png" alt="Relay" width="128" height="128">

# Relay

**Native macOS terminal for working with many coding agents in parallel.**

[![Release](https://img.shields.io/github/v/release/essedev/relay?label=release&color=2f81f7)](https://github.com/essedev/relay/releases/latest)
[![CI](https://img.shields.io/github/actions/workflow/status/essedev/relay/ci.yml?branch=main&label=CI)](https://github.com/essedev/relay/actions/workflows/ci.yml)
[![Homebrew](https://img.shields.io/badge/install-brew%20cask-FBB040?logo=homebrew&logoColor=white)](#installation)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**English** · [Italiano](README.it.md) · [User guide](docs/GUIDE.md)

</div>

<p align="center">
  <img src="docs/images/hero.png" alt="Relay running several agent sessions in parallel across workspaces" width="900">
</p>

Native macOS terminal for working with many coding agents in parallel: reliable agent state (via
Claude Code and Codex hooks), workspaces that keep projects apart, and a triage view for when a dozen
sessions are running at once. Fast and lightweight.

Status: baseline complete and distributed via a Homebrew tap. Workspace -> pane -> tab -> terminal,
agent runtime with badges and notifications, split panes and multiple windows, layout persistence,
assisted resume, kanban triage dashboard, workspace groups and archive, automatic workspace naming
(no setup needed, an LLM if you want better names), onboarding, an in-app guide, twelve themes.
Engine v1 is SwiftTerm behind the
`TerminalEngine` abstraction (libghostty a future backend). Decisions, benchmarks and research logs
live in `docs/research/` (`CYCLES.md`).

## Installation

```sh
brew install --cask essedev/relay/relay-terminal
```

Updates: `brew update && brew upgrade --cask relay-terminal`. The cask also links the `relay` and
`relay-cli` commands into your PATH, which the sections below use. When an update adds a hook
(0.17.0 added one, for API errors), Settings > Agents reports the hooks as not installed until you
run the setup again: it is idempotent and leaves your other hooks alone.

Alternatively, download the `.dmg` from the latest
[release](https://github.com/essedev/relay/releases/latest) and drag Relay into Applications. Relay
is not signed with an Apple Developer ID, so with the manual install macOS blocks the first launch:
open **System Settings > Privacy & Security** and click **Open Anyway** (once per version). The
cask clears the quarantine attribute for you, so installing with brew skips that step; the two
executables then live inside `Relay.app/Contents/MacOS`.

## What it does

- **Agent state you can trust.** Badges come from Claude Code and Codex hooks, not from parsing output, so
  they stay right under a wall of build logs. Per tab, and aggregated per workspace.
- **A three-step attention model.** A session that wants you is loud; one you have seen but not
  answered stays quiet in the background; replying clears it. Nothing stays lit forever, and
  nothing goes out before you have seen it.
- **Triage instead of hunting.** `Cmd+D` puts every session in the app on one screen, by default in
  four lanes by urgency (a grid layout is one toggle away), with type-to-filter and Return to jump.
- **Workspaces that stay organized.** Groups, pinning, an archive, and an order that only your
  drag - or a session finishing while you were elsewhere - can change.
- **Panes that hold tabs.** Split right or down; each pane keeps its own tab strip and selection.
  Any workspace can move to its own window, sessions and all.
- **Remappable shortcuts**, twelve themes, and terminals that are unloaded when unused so memory
  stays flat with dozens of tabs open: ~90 MB resident with one live terminal, ~92 MB with
  thirteen, and the input monitor adds 2.4µs worst case on a keystroke. Method and numbers in
  [`docs/research/PERF.md`](docs/research/PERF.md).

The full manual lives in **[docs/GUIDE.md](docs/GUIDE.md)**, and inside the app under
**Help > Relay Guide** (`Cmd+?`) - same content, generated from the same source.

<p align="center">
  <img src="docs/images/guide.png" alt="The in-app guide, open on the Workspaces and tabs section" width="900">
</p>

<p align="center">
  <img src="docs/images/dashboard.png" alt="The triage dashboard, sessions grouped in four lanes by state" width="900">
</p>

## Agent state (Claude Code and Codex hooks)

Relay shows each agent's state as a badge on the tab and, aggregated, on the workspace in the
sidebar (`running`, `needs_input`, `error`, done). State comes from native agent hooks, not from
parsing output.

```sh
relay-cli hooks setup all       # install Claude Code and Codex hooks
relay-cli hooks status all      # check both integrations
relay-cli hooks uninstall all   # remove only Relay-managed hooks
```

Then open Relay, start `claude` or `codex` in a tab and the badges update. `needs_input` stays until
you respond. The same setup is available per agent in Settings > Agents. Replace `all` with
`claude` or `codex` to manage just that agent; omitting the argument defaults to `claude`.

Claude hooks are added to `~/.claude/settings.json`; Codex hooks go in `~/.codex/hooks.json`
(or `$CODEX_HOME/hooks.json` when configured). Existing hooks are preserved. Use a Codex CLI
version with [native hook support](https://developers.openai.com/codex/hooks), and review the
configuration through `/hooks` after setup and whenever hook definitions change. The installed
status checks the file, not Codex's trust decision. Protocol and binding details are in
[docs/STATE_SCHEMA.md](docs/STATE_SCHEMA.md).

A turn killed by an API error - rate limit, overloaded, billing, no network - ends without
finishing, so it never reaches the "done" state. Claude Code exposes `StopFailure`, which Relay
catches to turn the tab red: ring, badge, a float to the top of the sidebar and a notification,
like any other signal you
have not seen. Every kind of error looks the same; the terminal has the details. Retrying clears
it. Codex hooks currently expose no equivalent failure event, so exact Codex API failures remain
visible in the terminal but cannot yet produce Relay's red error state; the badge can retain its
last state until another hook arrives. Interrupting a Codex turn returns it to idle without a
completion notification. After restarting Relay, the Resume bar supports both agents.

With the app launched from the bundle you also get macOS notifications when an agent asks for
input, hits an error, or finishes while you are not looking at the tab; clicking one brings that
tab up. From `make run` (no bundle) notifications are disabled.

To try the badges without a real agent session, inside a Relay tab:

```sh
relay-cli simulate            # fake chat ("coding" scenario), real events on the socket
relay-cli simulate permission # needs_input that stays pending
relay-cli simulate error      # a turn that dies on a rate limit, then a retry
relay-cli simulate burst --loops 3 --fast
```

To see the app full of activity: `relay --demo 5x4` opens five workspaces of four tabs with
concurrent simulated sessions (always over the real socket). Relay is single-instance, so quit a
running Relay first or the demo flag is ignored and the existing window just comes forward.

## Automatic workspace naming

A workspace with no folder is "Workspace 3", which stops being useful at the third one. Relay
renames it after what it is doing - the folder, a command running in one of its tabs, an active
agent session. The name pulses while it is being worked out.

This works with no setup: names are derived from those signals ("yellow-hub" becomes "Yellow Hub",
"npm run dev" becomes "Npm Dev"). Add an API key in **Settings > Agents > Workspace naming** and a
model writes them instead - better names, and "Regenerate name" gives you a different one (it works
without a key too, on the local rule). The default endpoint is OpenRouter with a cheap model, and a
name is a couple of hundred tokens; any OpenAI-compatible base URL and model work. Names you set by
hand are never overwritten.

## Shortcuts

Two axes, fixed: `Cmd+1..9` selects a workspace, `Option+1..9` a tab in the focused pane. The ones
worth learning first:

| Keys | Action |
| --- | --- |
| `⌘T` / `⌘W` | New tab, close tab |
| `⌘\` / `⇧⌘\` | Split right, split down |
| `⌘J` / `⇧⌘J` | Jump to the next/previous session that needs you |
| `⌘D` | Triage dashboard |
| `⌘F` / `⌘K` | Find in the terminal, clear it |
| `⌘?` | This app's guide |

Everything else - and every default, kept in sync automatically - is in the
[shortcut tables](docs/GUIDE.md#keyboard). They are remappable from Settings > Shortcuts (click a
combination, press the new one), with three fixed exceptions: the number axes above, the terminal
control keys (`⌃C`, `⌃D`, `⌃Z`, which belong to the program you are running), and the macOS menu
commands, `⌘?` included.

On international layouts `Option` doubles as AltGr: whenever it composes a printable character
(`Option+ò` = `@`), that character is typed into the terminal instead of triggering a shortcut.

## Appearance

Curated terminal themes (a full ANSI palette, so Claude Code, `git` and `ls` render in palette)
with matching chrome: twelve themes in six dark/light pairs (Relay, Solarized, Gruvbox, Tokyo
Night, Catppuccin, GitHub), plus font family, size and cursor blink. All from `Cmd+,`, all
persisted. The theme model lives in `Core` (`RelayTheme`), the single source for terminal and
chrome.

The title bar shows the active tab's context: the title set by the program (Claude Code sends the
chat name, zsh `user@host:path`), otherwise the current cwd abbreviated with `~`, otherwise the
workspace folder.

## Development

Requirements: Xcode/Swift 6, macOS 14+. The linters are **pinned**: `make tools` downloads the exact
SwiftFormat/SwiftLint releases into `.build/tools`, so CI and local runs use the same version. Do not
install them via brew for the quality gate (you would get a different version).

```bash
make build     # build
make tools     # download the pinned SwiftFormat/SwiftLint into .build/tools
make run       # launch the app (Relay window, no notifications)
make test      # test
make check     # full quality gate (lint + build + test)
make run-app   # launch from the .app bundle (notifications enabled)
make install-app  # install Relay.app into /Applications
make guide-md  # regenerate docs/GUIDE.md from the in-app guide
make dmg       # build .build/Relay-<version>.dmg (installer, not Developer ID signed)
make release   # publish the current release (VERSION): dmg -> GitHub Release -> brew tap
make help      # all targets
```

macOS notifications require a bundle id, so they only run from the packaged app
(`make run-app`/`install-app`), not from `make run`.

**The user guide is generated.** `docs/GUIDE.md` and the in-app guide come from the same source
(`Sources/WorkspaceModel/Guide*.swift`); a test fails if the committed file is out of date. Edit
the source, run `make guide-md`. The screenshots above come from `scripts/screenshots.sh`, which
drives an isolated demo instance so it never touches your own layout or preferences.

**Distribution**: the version lives in `./VERSION` (semver). To release: bump `VERSION`,
`make check`, commit, then `make release` (routine documented in `CLAUDE.md`). The installer is not
Developer ID signed or notarized, so first launch requires "Open Anyway"; Developer ID signing +
notarization is not set up yet.

## Documentation

- **[`docs/GUIDE.md`](docs/GUIDE.md)** - the user guide: everything Relay does, generated from the
  in-app guide.

The rest is internal and in Italian (the English-facing surface is this README and the guide).

- `docs/ARCHITECTURE.md` - product thesis, modules, budget, engine, anti-patterns.
- `docs/ROADMAP.md` - what is missing and in which order (baseline complete; next round TBD).
- `docs/research/CYCLES.md` - the work log, one entry per round (older ones in `cycles-archive/`).
- `docs/CONVENTIONS.md` - code, test and process rules.
- `docs/STATE_SCHEMA.md` - persistence schema and agent event protocol.
- `docs/features/*.md` - one file per area, with the invariants and the traps already paid for:
  `attention.md`, `agent-runtime.md`, `terminal.md`, `sidebar.md`, `workspace-groups.md`,
  `split-panes.md`, `windows.md`, `keyboard.md`, `workspace-naming.md`, `guide.md`,
  `persistence.md`, `distribution.md`.
- `CLAUDE.md` - operational guide for the agent, deliberately short: it points at the files above.

## License

Relay is [MIT licensed](LICENSE). It bundles SwiftTerm (MIT) as its terminal engine and
swift-argument-parser (Apache-2.0); their notices are in [NOTICE](NOTICE), shipped inside the app
under `Relay.app/Contents/Resources`.
