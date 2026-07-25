# Conventions

Regole di stile, qualità, test e processo. Struttura moduli e regole di dipendenza sono in
`ARCHITECTURE.md`.

## Lingua

- Codice, identificatori, commit: inglese (vedi "Commit E Branch" per lo stato reale della storia).
- Commenti e documentazione interna (`docs/`, `CLAUDE.md`): italiano.
- **README: `README.md` è in inglese**, è la vetrina pubblica linkata dal cask; `README.it.md` è la
  traduzione italiana. I due si aggiornano insieme: una modifica a uno solo è un bug.
- UI dell'app: inglese (prodotto per sviluppatori, non solo mercato italiano).

## Stile E Lint

- **SwiftFormat** per la formattazione, **SwiftLint** per le regole. Config committate nel
  repo, attive dal primo commit. Cosa impone davvero il gate: `make lint` gira
  `swiftformat --lint` + `swiftlint --strict`, quindi **ogni warning di SwiftLint è un errore**; i
  warning del **compilatore** invece non fanno fallire la build (nessun `-warnings-as-errors`), sono
  una regola di igiene che teniamo a zero a mano. Le versioni degli strumenti sono
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
  **Un'eccezione, esplicita e sotto tetto**: il composition root (`AppController`) è per natura
  wiring, e le sue `AppController+*.swift` (navigazione, menu, dashboard, onboarding, finestre,
  stats) sono ammesse purché ognuna resti *cablaggio* di un'area - se una di quelle extension inizia
  a contenere decisioni di dominio, quella logica va in un tipo suo (è così che sono nati
  `ShortcutRuntime`, `FullOverlayPresenter`, `NamingController`). Il tetto vale comunque: nessun file
  oltre i limiti, e la regola non si estende ad altri tipi.
- No force unwrap / force try. `force_unwrapping` è opt-in in `.swiftlint.yml` e **non esclude i
  test**: la regola vale anche lì (`XCTUnwrap` e `#require` fanno lo stesso lavoro dando un
  messaggio migliore). Se in futuro servisse allentarla nei test, va aggiunta un'esclusione nel
  config, non lasciata implicita nel doc.
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
2. doc di **comportamento** aggiornata nello stesso commit (vedi sotto);
3. per feature performance-sensibili: misura contro i budget, non impressioni;
4. nessun file oltre i limiti, nessun warning nuovo.

La regola "doc e codice nello stesso commit" non vale allo stesso modo per tutta la doc, e vale la
pena dirlo invece di violarla in silenzio:

- **doc di comportamento e di formato** - `STATE_SCHEMA.md` (schema di persistence e protocollo
  eventi), i gotcha di `CLAUDE.md`, `ARCHITECTURE.md` dove descrive invarianti: **stesso commit del
  codice**, senza eccezioni. Sono ciò su cui si basa chi legge per scrivere codice nuovo: disallineate
  fanno danno attivo, e uno schema in ritardo di un commit è già sbagliato.
- **narrativa di release** - il racconto del giro di lavoro (l'aggiornamento dello stato in cima a
  `CLAUDE.md`, le voci di `ROADMAP.md`): può arrivare in un commit `docs:` dedicato subito dopo, come
  di fatto succede. È cronaca, non contratto.

## Commit E Branch

- Conventional Commits in inglese (`feat`, `fix`, `refactor`, `docs`, `chore`, `test`,
  `perf`). Nota onesta: il tipo/scope è sempre inglese, ma dai dintorni di 0.8.0 molti *subject*
  sono in italiano. La regola resta l'inglese e vale da qui in avanti; la storia non si riscrive.
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
