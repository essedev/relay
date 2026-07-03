# Relay

Terminale macOS nativo per lavorare con molti coding agent in parallelo: stati agente
affidabili (via hook Claude Code), organizzazione a workspace (sidebar con pin e riordino,
dashboard overview), veloce e leggero.

Stato: V0 (Workspace -> Tab -> terminale) + agent runtime. Engine v1 SwiftTerm dietro l'astrazione
`TerminalEngine` (libghostty backend futuro). Decisioni, benchmark e log della ricerca:
`docs/research/` (`CYCLES.md`).

## Installazione

```sh
brew install --cask essedev/relay/relay
```

Aggiornamenti: `brew update && brew upgrade --cask relay`. In alternativa scarica il `.dmg`
dall'ultima [release](https://github.com/essedev/relay/releases/latest) e trascina Relay in
Applications.

L'app non è firmata con Developer ID Apple: al primo avvio macOS la blocca. Apri **Impostazioni di
Sistema > Privacy e Sicurezza** e premi **Apri comunque** (una volta sola per versione).

## Sviluppo

Requisiti: Xcode/Swift 6, macOS 14+. Per lint: `brew install swiftlint swiftformat`.

```bash
make build     # build
make run       # avvia l'app (finestra Relay, senza notifiche)
make test      # test
make check     # giro qualità completo (lint + build + test)
make run-app   # avvia dal bundle .app (notifiche attive)
make install-app  # installa Relay.app in /Applications
make dmg       # crea .build/Relay-<version>.dmg (installer, non firmato Developer ID)
make release   # pubblica la release corrente (VERSION): dmg -> GitHub Release -> tap brew
make help      # tutti i target
```

Le notifiche macOS richiedono un bundle id, quindi girano solo dall'app impacchettata
(`make run-app`/`install-app`), non da `make run`.

**Distribuzione**: la versione sta in `./VERSION` (semver). Per rilasciare: bumpa `VERSION`,
`make check`, commit, poi `make release` (routine in `CLAUDE.md`). L'installer non è firmato con
Developer ID né notarizzato, quindi il primo avvio richiede "Apri comunque"; la meccanica di firma
Developer ID + notarizzazione non è ancora in piedi.

## Scorciatoie

- `Cmd+N` nuovo workspace (senza cartella, parte da home).
- `Cmd+O` apri una cartella come workspace.
- `Cmd+T` nuova tab, `Cmd+W` chiudi tab, `Cmd+Shift+W` chiudi workspace.
- `Cmd+1..9` seleziona workspace, `Option+1..9` seleziona tab (i due assi, fissi).
- `Ctrl+Tab` / `Ctrl+Shift+Tab` scorri le tab, `Cmd+Option +/-` scorri i workspace.
- `Cmd+J` / `Cmd+Shift+J` salta alla prossima/precedente tab che richiede attenzione.
- `Cmd+F` cerca nel terminale, `Cmd+G` / `Cmd+Shift+G` risultato successivo/precedente,
  `Cmd+K` pulisce il terminale.
- `Cmd +/-` zoom del terminale, `Cmd+0` dimensione originale.
- `Cmd+B` mostra/nasconde la sidebar, `Cmd+,` impostazioni.

Le scorciatoie (tranne i select-by-number e i comandi di sistema) sono **rimappabili** da
Impostazioni > Shortcuts: clicca una combinazione, premi la nuova (conflitti segnalati, reset
disponibile). La finestra si sposta trascinando dalla fascia del titolo in alto (non dal
corpo/terminale); doppio click sulla fascia = zoom, come una title bar nativa.

## Aspetto

Tema del terminale curato (palette ANSI, quindi Claude Code/`git`/`ls` in palette), con chrome
coerente. Dodici temi in sei coppie dark/light (Relay, Solarized, Gruvbox, Tokyo Night,
Catppuccin, GitHub),
scelta del font family (monospace installati), dimensione font e blink del cursore, tutto regolabile
dal pannello impostazioni (`Cmd+,`, master-detail con ricerca) e persistito. Il modello di tema vive
in `Core` (`RelayTheme`), unica fonte per terminale e chrome.

La title bar mostra il contesto della tab attiva: il titolo impostato dal programma (Claude Code
manda il nome della chat, zsh `user@host:path`), altrimenti la cwd corrente (OSC 7) abbreviata con
`~`, altrimenti la cartella del workspace.

## Stato agente (hook Claude Code)

Relay mostra lo stato di ogni agente come badge sulla tab e, aggregato, sul workspace nella sidebar
(`running`, `needs_input`, completato). Lo stato arriva dagli hook Claude Code, non dal parsing
dell'output.

```bash
relay-cli hooks setup       # installa gli hook in ~/.claude/settings.json (convivono con Otty)
relay-cli hooks status      # verifica
relay-cli hooks uninstall   # rimuove solo gli hook di Relay
```

Poi apri Relay, avvia `claude` in una tab e i badge si aggiornano. `needs_input` resta finché non
rispondi. Dettagli protocollo/binding in `docs/STATE_SCHEMA.md`.

Con l'app avviata dal bundle (`make run-app`) arrivano anche le notifiche macOS quando un agente
chiede input o finisce mentre non stai guardando la tab (impostazioni e suono in `Cmd+,`; il primo
avvio chiede il permesso). Da `make run` (senza bundle) le notifiche sono disattivate.

Per provare i badge senza una sessione Claude vera, dentro una tab di Relay:

```bash
relay-cli simulate            # chat finta (scenario "coding"), eventi reali sul socket
relay-cli simulate permission # needs_input che resta in attesa
relay-cli simulate burst --loops 3 --fast
```

Per vedere l'app piena di attività: `relay --demo 5x4` apre 5 workspace da 4 tab con sessioni
simulate concorrenti (sempre via socket reale).

## Documentazione

- `docs/ARCHITECTURE.md` - tesi di prodotto, moduli, budget, engine, anti-pattern.
- `docs/ROADMAP.md` - cosa manca e in che ordine (prossimo: agent runtime + badge).
- `docs/CONVENTIONS.md` - regole di codice, test, processo.
- `docs/STATE_SCHEMA.md` - schema di persistence e protocollo eventi agente.
- `CLAUDE.md` - guida operativa per l'agent.
