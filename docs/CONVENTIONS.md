# Conventions

Regole di stile, qualità, test e processo. Struttura moduli e regole di dipendenza sono in
`ARCHITECTURE.md`.

## Lingua

- Codice, identificatori, commit: inglese.
- Commenti e documentazione tecnica (`docs/`, README, CLAUDE.md): italiano.
- UI dell'app: inglese (prodotto per sviluppatori, non solo mercato italiano).

## Stile E Lint

- **SwiftFormat** per la formattazione, **SwiftLint** per le regole. Config committate nel
  repo, attive dal primo commit. Zero warning tollerati in CI. Le versioni degli strumenti sono
  **pinnate** (binari dai release GitHub scaricati da `make tools` in `.build/tools`, versioni nel
  Makefile): CI e locale usano la stessa, così un upgrade upstream non rompe il lint su codice
  invariato. Bumpare la versione = aggiornare il Makefile e riformattare in un commit dedicato.
- Line length: 100.
- File: warning a 400 righe, errore a 500. Nessuna eccezione: se un file non ci sta, va
  spezzato in tipi o in un modulo.
- Type body: warning a 250 righe. Una classe da 1000 righe è un design error, non un file
  lungo.
- Vietato il pattern `AppDelegate+Feature.swift` come contenitore di logica: le extension
  servono per conformance e helper locali, non per spalmare un god object su 30 file.
- No force unwrap / force try nel codice di produzione (ok nei test).
- No `print`: logging solo via `os.Logger` (`Core.RelayLog`), subsystem unico dell'app, category =
  modulo. Mai segreti o payload utente nei log. Unica eccezione: `relay-cli`, dove `print` è
  l'output utente della CLI.

## Naming

- Tipi nominati per ruolo e responsabilità singola: `...Store`, `...Policy`, `...Coordinator`,
  `...Receiver`, `...Installer`. Niente `Manager`/`Helper`/`Utils` contenitori generici.
- Un tipo pubblico principale per file; il file si chiama come il tipo.
- Gli stati sono enum esaustivi, non stringhe o bool combinati.

## Concurrency

- Swift 6 strict concurrency abilitata (`complete`) dal primo giorno.
- Store osservati dalla UI: Observation framework, confinati al MainActor. `AppSettings` è
  `@MainActor`; `WorkspaceStore`/`Workspace`/`Tab` restano non-`@MainActor` ma non-`Sendable`, e
  ogni chiamante (composition root, coordinator, autosave) è già sul MainActor.
- Runtime (socket receiver): `@unchecked Sendable` con stato confinato a una `DispatchQueue`
  dedicata; il resto usa tipi `Sendable` espliciti.
- Structured concurrency (`Task`, `AsyncStream`) come default; le `DispatchQueue` dedicate sono
  ammesse dove servono davvero (il receiver socket con `DispatchSource` per accept/read e il vnode
  watcher del self-heal).

## Error Handling

- Errori tipizzati per modulo (`enum ...Error: Error`).
- Nessun `catch` silenzioso: o si gestisce, o si logga con contesto, o si propaga.
- I path che toccano file utente (hook installer, persistence) falliscono in modo esplicito e
  reversibile: backup prima, validazione dopo.

## Test

Regola base: logica nuova = test nello stesso commit. Bug fix = regression test che prima
fallisce.

- **Unit** (Swift Testing, `swift test` per package): tutta la logica pura. In particolare:
  - mapping eventi -> stati (`ClaudeHookStateMapper`, `ClaudeHookEvent`);
  - transizioni del marker di attenzione e aggregazione badge;
  - policy lifecycle surface (lazy/LRU) come tipo puro (`SurfaceEvictionPolicy`);
  - serializzazione protocollo (`AgentStateEvent` round-trip) e persistence layout.
- **Installer**: fixture di `settings.json` (vuoto, con Otty, con hook utente) -> assert su
  idempotenza, backup + pruning, preservazione, uninstall pulito, round-trip su disco.
- **Integration**: receiver socket end-to-end (avvia receiver, invia JSON lines, assert sul
  callback), incluso il self-heal (rebind quando il socket sparisce). Niente mock del trasporto.
- **UI**: minimale. La correttezza sta nei moduli sotto; non c'è una suite UI fragile né uno smoke
  di avvio dell'app (l'eseguibile non ha un test target).
- **Performance**: strumentazione integrata accesa da `RELAY_PERF=1` (`PerfSampler`: latenza input,
  RSS, surface vive), misurata a mano contro i budget di `ARCHITECTURE.md`. Numeri e metodo in
  `docs/research/PERF.md`. Non c'è un target `make perf`.

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
make install    # swift package resolve
make build      # build (debug)
make run        # build e lancia l'app (senza notifiche)
make test       # unit + integration di tutti i package
make lint       # SwiftFormat --lint + SwiftLint --strict
make format     # SwiftFormat write
make check      # lint + build + test (definition of done)
make bundle / run-app / install-app / dmg / release   # .app, installer, pubblicazione
make icon / clean
```

Vedi `make help` per l'elenco completo.

## CI

- GitHub Actions, runner macOS: `make check` + `swift build -c release` su ogni push/PR
  (`.github/workflows/ci.yml`).
- CI attiva dal primo commit del repo.

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
