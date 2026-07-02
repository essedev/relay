# Relay - guida per l'agent

Terminale macOS nativo agent-aware. Leggi `docs/ARCHITECTURE.md` prima di toccare la struttura
e `docs/CONVENTIONS.md` prima di scrivere codice.

## Comandi

- `make build` / `make test` / `make run` / `make check` (definition of done prima di un commit
  grosso e sempre prima di proporre un push).
- Lint: serve `brew install swiftlint swiftformat` (non ancora installati in locale).

## Mappa moduli (dipendenze solo verso il basso)

- `Core` - primitivi (logging). Nessuna dipendenza.
- `AgentProtocol` - tipi evento/stato agente, puro. Niente I/O, niente AppKit.
- `AgentRuntime` - store/receiver stato agente (actor).
- `WorkspaceModel` - workspace/tab/pane, aggregazione severità. Niente AppKit.
- `TerminalEngine` - astrazione engine + backend SwiftTerm. **Nessun tipo SwiftTerm deve
  trapelare fuori da qui.**
- `TerminalHostUI` - host AppKit della surface (path caldo, latenza).
- `Panels` - pannelli SwiftUI isolati (sidebar, dashboard).
- `HookInstaller` - hook Claude in ~/.claude/settings.json.
- `RelayApp` (`Sources/relay`) - composition root. Se cresce oltre il wiring, manca un modulo.
- `CLI` (`Sources/relay-cli`) - eseguibile `relay`.

## Regole che non si violano

- AppKit sul path caldo (terminale, input); SwiftUI solo nei pannelli isolati.
- Lazy + budget: niente priming, niente risorse pesanti prima del bisogno (vedi principi in
  ARCHITECTURE). Cap scrollback.
- Mai `print` per logging (usa `RelayLog`); nel CLI il print è output utente, ok.
- Mai committare `.env*`, segreti, file di auth. Mai hardcodare valori estetici nei pannelli:
  usa il design system (principio UI 6 in ARCHITECTURE).
- Swift 6 strict concurrency: store osservati `@MainActor`, runtime come actor.

## Gotcha noti

- libghostty non è ancora embeddabile stabile: engine v1 = SwiftTerm. Non reintrodurre zig o
  binari di fork senza una decisione esplicita (vedi ARCHITECTURE, sezione engine).
- L'app è un eseguibile SwiftPM per ora; il bundling `.app` (Info.plist, entitlements, firma per
  notifiche) arriva quando serve.
