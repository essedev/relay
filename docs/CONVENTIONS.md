# Conventions

Bozza per il repo app (diventerà `docs/CONVENTIONS.md`). Struttura moduli e regole di
dipendenza sono in `ARCHITECTURE.md`: questo file copre stile, qualità, test e processo.

## Lingua

- Codice, identificatori, commenti, commit, doc tecnica: inglese.
- UI dell'app: inglese (prodotto per sviluppatori, non solo mercato italiano).

## Stile E Lint

- **SwiftFormat** per la formattazione, **SwiftLint** per le regole. Config committate nel
  repo, attive dal primo commit. Zero warning tollerati in CI.
- Line length: 100.
- File: warning a 400 righe, errore a 500. Nessuna eccezione: se un file non ci sta, va
  spezzato in tipi o in un modulo.
- Type body: warning a 250 righe. Una classe da 1000 righe è un design error, non un file
  lungo.
- Vietato il pattern `AppDelegate+Feature.swift` come contenitore di logica: le extension
  servono per conformance e helper locali, non per spalmare un god object su 30 file.
- No force unwrap / force try nel codice di produzione (ok nei test).
- No `print`: logging solo via `os.Logger`, subsystem unico dell'app, category = modulo.
  Mai segreti o payload utente nei log.

## Naming

- Tipi nominati per ruolo e responsabilità singola: `...Store`, `...Policy`, `...Coordinator`,
  `...Receiver`, `...Installer`. Niente `Manager`/`Helper`/`Utils` contenitori generici.
- Un tipo pubblico principale per file; il file si chiama come il tipo.
- Gli stati sono enum esaustivi, non stringhe o bool combinati.

## Concurrency

- Swift 6 strict concurrency abilitata (`complete`) dal primo giorno.
- Store osservati dalla UI: `@MainActor` + Observation framework.
- Runtime (socket receiver, timeline): actor o tipi `Sendable` espliciti.
- Niente `DispatchQueue` ad hoc: structured concurrency (`Task`, `TaskGroup`, `AsyncStream`).

## Error Handling

- Errori tipizzati per modulo (`enum ...Error: Error`).
- Nessun `catch` silenzioso: o si gestisce, o si logga con contesto, o si propaga.
- I path che toccano file utente (hook installer, persistence) falliscono in modo esplicito e
  reversibile: backup prima, validazione dopo.

## Test

Regola base: logica nuova = test nello stesso commit. Bug fix = regression test che prima
fallisce.

- **Unit** (Swift Testing, `swift test` per package): tutta la logica pura. In particolare:
  - mapping eventi -> stati: table-driven, la tabella in `ARCHITECTURE.md` è la fixture;
  - aggregazione severità pane -> tab -> workspace;
  - policy lifecycle surface (lazy/LRU) come tipo puro;
  - parsing/serializzazione protocollo con fixture JSON committate.
- **Installer**: fixture di `settings.json` reali (vuoto, con Otty, con hook utente, JSON
  rotto) -> assert su idempotenza, backup, preservazione, uninstall pulito.
- **Integration**: receiver socket end-to-end (avvia receiver, invia JSON lines, assert sullo
  store). Niente mock del trasporto.
- **UI**: minimale. Smoke di avvio app; nessuna suite UI fragile. La correttezza sta nei
  moduli sotto.
- **Performance**: harness dedicato che misura contro i budget di `ARCHITECTURE.md` (latenza
  input, tempo di realize surface, memoria per surface). Eseguito manualmente con `make perf`,
  in CI solo come smoke non bloccante.

## Definition Of Done

Una feature è finita quando:

1. `make check` verde (format, lint, build, test);
2. doc aggiornata nello stesso commit se cambia comportamento, schema o protocollo;
3. per feature performance-sensibili: misura contro i budget, non impressioni;
4. nessun file oltre i limiti, nessun warning nuovo.

## Commit E Branch

- Conventional Commits in inglese (`feat`, `fix`, `refactor`, `docs`, `chore`, `test`,
  `perf`).
- Un commit = un'unità logica. Mai refactor + feature insieme.
- Trunk-based su `main` finché il progetto è single-person; feature branch + PR se entra
  altra gente.
- Push solo su comando esplicito; prima del push, `make check` sempre.

## Makefile

Target standard (convenzione Yellow):

```text
make install    # bootstrap: toolchain check, GhosttyKit fetch/build
make build      # build app + CLI
make run        # build e lancia l'app
make test       # unit + integration di tutti i package
make lint       # SwiftLint + SwiftFormat --lint
make format     # SwiftFormat write
make check      # format-check + lint + build + test
make perf       # harness performance contro i budget
make clean
```

## CI

- GitHub Actions, runner macOS: `make check` su ogni push/PR.
- Cache di GhosttyKit e delle build SwiftPM: target < 10 minuti.
- CI attiva dal primo commit del repo, non "quando avremo tempo".

## Documentazione Del Repo App

Set minimo alla creazione:

- `README.md`: cosa fa, come si builda, link ai doc.
- `CLAUDE.md`: convenzioni operative per l'agent, comandi, gotcha.
- `docs/ARCHITECTURE.md`: trasferita e mantenuta da questa analisi.
- `docs/CONVENTIONS.md`: questo file.
- `docs/STATE_SCHEMA.md`: schema di persistence (snapshot layout) e protocollo eventi, al
  posto del `DATABASE_SCHEMA.md` (niente database in v1). Aggiornato nello stesso commit di
  ogni cambio schema.

Doc e codice cambiano nello stesso commit, o la doc è troppo dettagliata.
