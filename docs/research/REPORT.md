# Analisi Base Terminale Agent-Aware

Data: 2026-07-02  
Scope: macOS-only, GPL accettabile, obiettivo MVP ispirato a `cmux` con stati agente stile Otty.

## Aggiornamento 2026-07-02 (Cycle 5)

Il verdetto engine qui sotto (libghostty/GhosttyKit) è stato **rivisto**. Lo spike (Cycle 4) ha
trovato che libghostty non è ancora una libreria embeddabile stabile: solo il parser
`libghostty-vt` è in arrivo, la C API con rendering è internal-only e si builda solo da sorgente
con zig, che sul SDK macOS 26.5 di questa macchina non linka. Decisione corrente: **engine v1
SwiftTerm dietro l'astrazione `TerminalEngine`, libghostty come backend futuro**. Dettagli in
`CYCLES.md` (Cycle 4-5) e `ARCHITECTURE.md`. Il resto di questo report resta valido come analisi
di prodotto e di anti-pattern.

## Verdetto

La scelta migliore non è forkare `cmux` intero. La strada più solida è costruire una nuova app macOS nativa sopra un engine embeddabile, con `libghostty`/`GhosttyKit` come candidato principale, usando `cmux` come reference di prodotto e Otty come reference di protocollo agent-state.

Se serve massima velocità di prototipazione e si accetta un compromesso su natività e performance, l'alternativa più rapida è `xterm.js` con host Electron/WebView. Se invece vogliamo un prodotto macOS nativo, veloce e controllabile nel tempo, `libghostty` resta il substrato più convincente tra quelli analizzati.

`cmux` va considerato come miniera di pattern e, al limite, componenti da isolare sotto GPL. Come base diretta porta troppo peso: browser, iOS, cloud/presence, remote daemon, webviews, CLI monolitica, hook per molti agenti, workspace restore avanzato e dipendenza dal fork Manaflow di Ghostty.

## Repo Analizzate

| Repo | Commit | File | Size | Ruolo migliore |
| --- | ---: | ---: | ---: | --- |
| `manaflow-ai/cmux` | `026fa6a` | 11961 | 686M | Reference prodotto / fork solo se accettiamo monolite GPL |
| `ghostty-org/ghostty` | `c22df09` | 5696 | 133M | Engine embeddabile nativo macOS |
| `gnachman/iTerm2` | `6daad94` | 7063 | 232M | Reference automazione/status, fork diretto sconsigliato |
| `alacritty/alacritty` | `bdb72b3` | 322 | 50M | Core Rust leggero, app shell da costruire |
| `wez/wezterm` | `09d0570` | 1785 | 244M | Reference mux/automation, fork possibile ma pesante |
| `raphamorim/rio` | `2bb89d2` | 572 | 34M | Reference moderna Rust/WebGPU, embedding debole |
| `contour-terminal/contour` | `834edcd` | 491 | 32M | Reference VT backend, C++/Qt pesante |
| `Eugeny/tabby` | `6955c4f` | 857 | 69M | Reference Electron/plugin/split, non base nativa |
| `xtermjs/xterm.js` | `8aab310` | 691 | 30M | Miglior embedding web/headless |

## Ranking Per Strategia

### Nuova App Nativa Con Engine Embeddabile

1. `Ghostty/libghostty`: migliore fit. MIT, API C, esempi Swift/XCFramework, Metal su macOS, separazione VT/render/formatter.
2. `xterm.js`: ottimo se accettiamo web stack. Rapidissimo per UI agent-aware, ma non è nativo.
3. `alacritty_terminal`: core Rust pulito, ma richiede UI, split, sidebar, IPC e render shell.
4. `wezterm-term` / `wezterm-surface`: core maturo, ma workspace monorepo e mux rendono l'estrazione meno pulita.
5. `Contour vtbackend`: architettura modulare, ma C++23/Qt lo rende costoso per macOS nativo.

### Fork Diretto Di Una App

1. `Ghostty`: miglior fork diretto permissivo; bisogna aggiungere tab verticali, sidebar agent e IPC ricco.
2. `WezTerm`: mux/CLI/Lua forti, ma UI cross-platform pesante e poco macOS-native.
3. `cmux`: feature match massimo, ma monolite GPL e superficie enorme.
4. `iTerm2`: automazione e status molto forti, ma ObjC/Swift legacy e monolite GPL.
5. `Rio`: moderno ma meno maturo su automation/restore.
6. `Tabby`: utile come reference, ma Electron va contro il target nativo.
7. `Contour`: buono VT, debole come app agent con split/sidebar.
8. `Alacritty`: non ha tab/split, quindi è più engine che fork app.

## cmux

Punti forti:
- Ha già quasi tutto: tab verticali/sidebar, pane/split, notification rings, socket API, CLI, hooks, session restore.
- Usa `libghostty`/`GhosttyKit`, quindi performance e rendering sono allineati alla direzione migliore.
- Ha documentazione e test su notifiche, hooks, socket, session restore.

Rischi:
- Repo enorme e ibrida: Swift/AppKit, SwiftPM, Zig/GhosttyKit, Go daemon, Bun/webviews, Workers, iOS.
- `CLI/cmux.swift` è monolitico e contiene molte responsabilità.
- Molte feature non-MVP sono intrecciate: browser, cloud, iOS, feed, remote, hibernation, multi-agent integrations.
- Dipende dal fork `manaflow-ai/ghostty`, non solo upstream Ghostty.
- GPL-3.0-or-later: per noi va bene, ma resta vincolo forte.

File cmux più rilevanti:
- `scripts/setup.sh`
- `scripts/ensure-ghosttykit.sh`
- `.gitmodules`
- `Packages/macOS/CmuxTerminal/Sources/CmuxTerminal/Surface/TerminalSurface.swift`
- `Sources/GhosttyTerminalView.swift`
- `Sources/Workspace.swift`
- `Sources/TabManager.swift`
- `Packages/macOS/CmuxControlSocket/Sources/CmuxControlSocket/Server/SocketControlServer.swift`
- `Sources/SessionPersistence.swift`
- `Sources/TerminalNotificationStore.swift`
- `CLI/CMUXCLI+AgentHookDefinitions.swift`
- `Resources/bin/cmux-claude-wrapper`

## Agent State: Protocollo Consigliato

Separare sempre stato shell e stato agente.

### Evidenza Otty Locale

Gli hook Otty installati in `~/.claude/settings.json` sono semplici e leggibili. Ogni evento Claude Code chiama:

```text
/Applications/Otty.app/Contents/Resources/agent-integration/claude/otty-hook.sh <state> "$PPID" [ctx]
```

Mapping trovato:

| Claude hook | Stato inviato a Otty | Nota |
| --- | --- | --- |
| `SessionStart` | `idle` | inizializza sessione come pronta |
| `UserPromptSubmit` | `processing` | l'utente ha inviato un prompt |
| `PreToolUse` | `processing` | l'agente sta lavorando/usando tool |
| `PostToolUse` | `processing` | resta in processing dopo il tool |
| `PermissionRequest` | `awaiting` | richiede input/approval, con contesto |
| `Stop` | `idle` | turno finito |

Lo script Otty (`/Applications/Otty.app/Contents/Resources/agent-integration/claude/otty-hook.sh`) fa tre cose chiave:

1. Legge il payload JSON da stdin.
2. Estrae `session_id`, preferendo `CLAUDE_SESSION_ID` quando presente.
3. Chiama il CLI Otty in background:

```text
otty-cli state:claude session-id="$sid" state="$state" bypass="$bypass"
```

Per `PermissionRequest` aggiunge anche:

```text
context-b64="$ctx"
```

Il flag `bypass` viene calcolato leggendo l'argv del processo Claude (`$PPID`) e cercando `--dangerously-skip-permissions`. Questo è importante per noi: lo stato agente affidabile non richiede parsing dell'output terminale, ma solo hook + session id + piccolo receiver IPC.

Stato agente minimo:
- `agent.session.start`: agent, sessionId, workspaceId, paneId, pid, cwd, transcriptPath, resumeCommand.
- `agent.state`: sessionId, state (`running`, `idle`, `needs_input`, `error`, `unknown`), reason, toolName, turnId, source, confidence, timestamp.
- `agent.notification`: sessionId, severity, title, subtitle, body, dedupeKey, requiresAttention.
- `agent.session.end`: sessionId, exitReason, exitCode, finalState.
- `agent.resume.set`: sessionId, sanitized command, cwd, configRoot.

Stato shell minimo:
- `command_running`
- `command_done`
- `command_failed`
- `command_awaiting_input`

Fonti stato:
- Hook agente: fonte autorevole.
- OSC `9;4`: progress shell.
- OSC `9`, `99`, `777`: compat notifiche.
- Shell integration `OSC 133`: command boundary/exit status.
- Euristiche prompt: solo fallback, sempre con delay e confidence bassa.

Pitfall:
- Non confondere `SubagentStop` con fine del turno principale.
- Non notificare `done` se finisce solo un subagent.
- Non salvare prompt, token, credenziali o selector vecchi nel resume.
- `awaiting input` euristico deve cancellarsi al primo input/output.
- PID/env possono diventare stale; meglio legare sessione a pane/surface e TTY.

## Spike Di Build

Esito: build non completata, con blocker utili per la decisione.

Toolchain trovata:
- `xcodebuild`: Xcode 26.6, build 17F113.
- `swift`: Apple Swift 6.3.3.
- `zig`: mancante.
- `bun`: mancante.

Submodule:
- `ghostty`: inizializzato a `541e5e8`.
- `homebrew-cmux`: inizializzato a `a5f372e`.
- `vendor/bonsplit`: inizializzato a `01751ef`.

`./scripts/ensure-ghosttykit.sh` fallisce subito:

```text
Error: zig is not installed.
Install via: brew install zig
```

`xcodebuild -resolvePackageDependencies` fallisce prima della risoluzione per Xcode/CoreSimulator:

```text
A required plugin failed to load. Please ensure system content is up-to-date — try running 'xcodebuild -runFirstLaunch'.
Library not loaded: /Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/CoreSimulator
```

Interpretazione:
- `cmux` richiede setup macchina non banale.
- Anche senza build completa, la pipeline mostra che `GhosttyKit` e submodule sono un costo operativo centrale.
- Prima di qualsiasi fork reale servono `zig`, `bun` se tocchiamo webviews, Xcode first launch/system content e cache GhosttyKit.

## Prodotto Consigliato

Incluso:
- App macOS Swift/AppKit o SwiftUI con wrapper terminale.
- Engine: `libghostty`/`GhosttyKit` come prima scelta.
- Split e tab verticali semplici.
- Sidebar con branch/cwd/status agente.
- Protocollo agent-state esplicito + CLI/socket minimale.
- Hook Claude Code come prima integrazione fondativa: gli stati affidabili devono arrivare dagli hook, non da euristiche sul testo.
- Notifiche macOS + badge pane/tab.
- Resume minimo basato su sessionId e comando sanitizzato.
- UI veloce, funzionale e curata: niente orchestrator pesante, niente feature laterali che competono con il terminale.

Fuori dal prodotto:
- Browser automation.
- iOS companion.
- Cloud VM / presence / sync.
- Agent teams avanzati.
- Skills marketplace.
- Remote tmux/SSH avanzato.
- Hibernation automatica agenti.
- Hook per tutti gli agenti: il core deve supportare il protocollo, ma il prodotto parte da Claude Code e aggiunge altri agenti solo se servono davvero.

## Piano Spike 2-3 Giorni

1. Preparare macchina: `zig`, `bun`, `xcodebuild -runFirstLaunch` se necessario, verifica GhosttyKit.
2. Compilare `cmux` senza modifiche e misurare tempi/setup.
3. Compilare un esempio `libghostty`/Swift o `GhosttyKit` minimale.
4. Prototipare UI macOS: una finestra, due pane, sidebar, stato mock agente.
5. Implementare micro-protocollo locale: `agent.state` via Unix socket o CLI.
6. Aggiungere hook Claude Code minimale e autorevole: `running`, `idle`, `needs_input`.
7. Decidere: fork `cmux`, fork `Ghostty`, oppure nuova app su `libghostty`.

## Decisione Raccomandata Ora

Procedere con due spike paralleli:

1. Spike A: compilare e tagliare mentalmente `cmux`, misurando quanto costa rimuovere browser/cloud/iOS.
2. Spike B: nuova app macOS minima con `libghostty`/`GhosttyKit` e protocollo agent-state.

Il criterio di scelta deve essere il tempo per arrivare a un MVP stabile, non il numero di feature già presenti. Al momento la probabilità più alta è: nuova app su `libghostty`, con `cmux` e Otty come reference.
