# Cycles 14-15 (archivio)

Il giro di pulizia dopo il baseline delle milestone: refactor a comportamento invariato, CI resa
deterministica, move-tab, poi le patch 0.7.3-0.7.6 (input internazionale, LRU, Runtime Stats, note
di release). Spostati qui dalla rotazione di `../CYCLES.md` (che tiene gli ultimi ~15).
Numerazione intatta: `Cycle 14` resta `Cycle 14`.

Le decisioni ancora vincolanti che nascono qui stanno in `../../DECISIONS.md`: strumenti di lint
pinnati (#1), eccezioni dell'input nella policy (#2), cap LRU soft (#3), Runtime Stats a richiesta
(#4), note di release dai conventional commit (#5).

## Cycle 14 - Pulizia codebase, CI deterministica, move-tab

### Obiettivo

Un giro di pulizia sistematica del codice (duplicazione, componenti UI, dead code) a comportamento
invariato, la messa in sicurezza della CI (rossa da due release) e una piccola funzione: spostare
una tab in un nuovo workspace.

### Pulizia (refactor a comportamento invariato)

Revisione sistematica, poi undici commit atomici, ognuno verificato (build + lint + test) e passato
a una **verifica adversariale commit per commit** (un agente scettico per commit):

- **Panels**: estratti i componenti condivisi `StatusDot`/`CommandChip`/`CloseButton` (prima
  duplicati a mano con dimensioni divergenti) e tokenizzati i font/tint ricorrenti nel design system.
- **Model**: `RelayTheme.copy` unico dietro i tre `withX`, helper `update`/`toggle` per i setter di
  `AppSettings` (via keypath, compatibile con Observation), `Array.move` generico, lookup `tab(id:)`
  condiviso.
- **Composition root**: `FullOverlayPresenter` unico per gli overlay full-window (mutua esclusione
  per costruzione, prima cablata a mano), `reveal(workspaceID:tabID:)` centralizzato, dead code
  rimosso.
- **Core/Engine**: trigger-policy della nomina estratta pura in `Core.NamingTriggerPolicy` (testata),
  conversione `NSColor(relay:)` unica in `TerminalEngine` (prima triplicata).
- **I/O**: errori di trasporto/backup non più inghiottiti (drain, LayoutStore), path hook
  shell-escaped, exit code del CLI.

La verifica adversariale ha intercettato due regressioni visive sfuggite (larghezza della pill del
recorder di shortcut e colore del comando nel popover update), poi corrette prima del push.

### CI deterministica (il version skew di SwiftFormat)

La CI era **rossa da 0.7.0**: falliva in ~15s sul lint. Causa: il workflow faceva `brew install
swiftformat` (sempre l'ultima), e una regola nuova (`redundantParens`, poi `wrapIfStatementBodies`)
bocciava codice invariato che la SwiftFormat locale, più vecchia, non vedeva. Ogni versione vede
errori diversi: `brew install` flottante rende la CI non-deterministica. Soluzione: strumenti
**pinnati** a versione fissa, scaricati come binari dai release GitHub in `.build/tools` (`make
tools`, stamp versionato per il bump); CI e locale girano la stessa versione. Il fix di codice vero
era di 3 righe (le parentesi che la versione pinnata vuole).

### Move to New Workspace

Dal menu contestuale di una tab (solo con >=2 tab) la si estrae in un nuovo workspace placeholder
**senza toccare la sessione viva**: lo store sposta lo stesso oggetto `Tab` (stesso `Tab.id`),
quindi la surface/pty resta intatta. Chiave: append del nuovo workspace + remove dall'origine nella
stessa mutazione sincrona, così il reconcile delle surface non sfratta la tab. Il nuovo workspace
eredita la cwd come `rootPath` e nasce `.default` (nominabile). Testato (stesso oggetto, no-op sui
casi limite).

### Esito

`make check` verde (279 test), CI di nuovo verde e **deterministica**. Undici commit di pulizia + il
fix CI + la funzione, rilasciati come patch 0.7.2.

## Cycle 15 - Rifiniture: input internazionale, LRU, osservabilità

### Obiettivo

Il giro di patch dopo il baseline delle milestone (0.7.3 -> 0.7.6): tre difetti emersi dall'uso
reale (tastiera italiana, contesto perso dalla LRU, nessuna visibilità sui consumi) più le note di
release. Nessuna feature grossa: correggere ciò che si rompe sotto le dita.

### Testo da `Option` vs scorciatoie (il giro completo)

Sui layout internazionali `Option` è anche AltGr: `Option+ò` compone `@`, `Option+è` compone `[`.
Relay intercettava quelle combinazioni come scorciatoie, quindi **i simboli non si potevano
digitare** nel terminale. Il primo fix (`924aee8`, 0.7.4) ha introdotto la policy pura
`Core.KeyboardTextInput`: se macOS produce testo stampabile da `Option` senza `Cmd/Ctrl`, quel testo
vince; il monitor non consuma l'evento e `OptionTextInterceptor` lo scrive UTF-8 nel PTY prima che il
kitty keyboard protocol lo codifichi come tasto modificato.

Ma la regola era **troppo larga**: sull'italiano anche `Option+1..9` compone simboli tipografici
(`Option+1` = `«`, `Option+2` = `™`), quindi la policy classificava come digitazione anche il
select-tab fisso e **`Option+1..9` smetteva di cambiare tab**. Un difetto tipico da regola universale
su un dominio con eccezioni.

Fix (`ec28342`): l'eccezione vive **dentro la policy**, non nei chiamanti. `Option`+cifra 1..9 senza
Shift non è mai testo. Così i tre consumatori (monitor di navigazione, interceptor verso il PTY,
recorder delle impostazioni) restano coerenti **per costruzione**, senza dipendere dall'ordine in cui
i local monitor vedono l'evento - la stessa logica che tiene il resto dell'input in un punto solo.
Tutto il resto continua a essere digitazione: `Option+ò`, `Option+Shift+cifra`, `Option+0`. Tradeoff
accettato ed esplicito: i simboli su `Option+cifra` non sono digitabili finché la scorciatoia esiste.
I flag dei modificatori sono passati come `OptionSet` puro (`KeyboardTextInput.Modifiers`), non come
quattro `Bool`.

Costo di non aver messo l'eccezione subito: una release (0.7.4) in cui le tab non si cambiavano da
tastiera su ogni layout non-US.

### LRU: proteggere il contesto recente

Il cap LRU sfrattava surface idle appena sopra il cap, anche quelle usate un minuto prima: lo
sfratto è un teardown SwiftTerm (scrollback perso, shell ricreata). `678ff3b` (0.7.5) aggiunge alla
policy pura (`SurfaceEvictionPolicy`) il concetto di tab **protetta** oltre a quello di tab con
lavoro vivo: mai la visibile, le tab del workspace attivo, quelle con attenzione fresca, quelle
toccate negli ultimi ~30 minuti. Il cap resta un **soft cap**: se i candidati non bastano si sfora,
perché sforare costa memoria mentre sfrattare costa contesto dell'utente.

### Runtime Stats

`2cf55ee` (0.7.6): pannello read-only da `View > Runtime Stats…` con RSS, CPU del processo,
workspace/tab e surface vive rispetto al cap. Il campionamento (`RuntimeStatsSampler`, ~2s) gira
**solo finché il pannello è aperto** e il timer muore in `windowWillClose`: è osservabilità a
richiesta, non polling permanente. Resta distinto da `PerfSampler`, che è dev tooling
(`RELAY_PERF`) e misura anche la latenza di input.

### Note di release dai conventional commit

`gh release create --generate-notes` produceva un body vuoto: genera dalle PR, e il repo è
trunk-based. `9cb3b61` lo sostituisce con `release-notes.sh`, che raggruppa per tipo i conventional
commit tra due tag, più `backfill-release-notes.sh` per riscrivere il body delle release già
pubblicate senza toccare tag, asset o cask.

### Esito

`make check` verde (291 test, inclusi i casi della policy: cifre riservate, `Option+Shift+cifra` e
`Option+0` restano testo). Su tastiera italiana funzionano **entrambi**: `Option+1..9` cambia tab e
`Option+ò` scrive `@`.
