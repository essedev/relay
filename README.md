# Relay

Terminale macOS nativo per lavorare con molti coding agent in parallelo: stati agente
affidabili (via hook Claude Code), organizzazione a workspace (sidebar con pin e riordino,
dashboard overview), veloce e leggero.

Stato: scheletro Fase 2. Engine v1 SwiftTerm dietro l'astrazione `TerminalEngine` (libghostty
backend futuro). Decisioni e benchmark: repo di ricerca `terminal-agent-analysis`.

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

## Documentazione

- `docs/ARCHITECTURE.md` - tesi di prodotto, moduli, budget, engine, anti-pattern.
- `docs/ROADMAP.md` - cosa manca e in che ordine (prossimo: agent runtime + badge).
- `docs/CONVENTIONS.md` - regole di codice, test, processo.
- `docs/STATE_SCHEMA.md` - schema di persistence e protocollo eventi agente.
- `CLAUDE.md` - guida operativa per l'agent.
