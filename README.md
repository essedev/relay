# Relay

Terminale macOS nativo per lavorare con molti coding agent in parallelo: stati agente
affidabili (via hook Claude Code), organizzazione a workspace (sidebar con pin e riordino,
dashboard overview), veloce e leggero.

Stato: V0 (Workspace -> Tab -> terminale) + agent runtime. Engine v1 SwiftTerm dietro l'astrazione
`TerminalEngine` (libghostty backend futuro). Decisioni e benchmark: repo di ricerca
`terminal-agent-analysis`.

## Sviluppo

Requisiti: Xcode/Swift 6, macOS 14+. Per lint: `brew install swiftlint swiftformat`.

```bash
make build     # build
make run       # avvia l'app (finestra Relay)
make test      # test
make check     # giro qualità completo (lint + build + test)
make help      # tutti i target
```

## Scorciatoie

- `Cmd+N` nuovo workspace (senza cartella, parte da home).
- `Cmd+O` apri una cartella come workspace.
- `Cmd+T` nuova tab, `Cmd+W` chiudi tab.
- `Cmd+1..9` seleziona workspace, `Option+1..9` seleziona tab (i due assi).
- `Cmd +/-` zoom del terminale, `Cmd+0` dimensione originale.
- `Cmd+,` impostazioni (tema, dimensione font).

## Aspetto

Tema del terminale curato (palette ANSI, quindi Claude Code/`git`/`ls` in palette), con chrome
coerente. Due temi di default (Relay Dark/Light), font e dimensione regolabili dalle impostazioni
(`Cmd+,`), persistiti. Il modello di tema vive in `Core` (`RelayTheme`), unica fonte per terminale
e chrome.

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

Per provare i badge senza una sessione Claude vera, dentro una tab di Relay:

```bash
relay-cli simulate            # chat finta (scenario "coding"), eventi reali sul socket
relay-cli simulate permission # needs_input che resta in attesa
relay-cli simulate burst --loops 3 --fast
```

## Documentazione

- `docs/ARCHITECTURE.md` - tesi di prodotto, moduli, budget, engine, anti-pattern.
- `docs/ROADMAP.md` - cosa manca e in che ordine (prossimo: agent runtime + badge).
- `docs/CONVENTIONS.md` - regole di codice, test, processo.
- `docs/STATE_SCHEMA.md` - schema di persistence e protocollo eventi agente.
- `CLAUDE.md` - guida operativa per l'agent.
