# Ricerca

Storia della ricerca che ha portato a Relay, importata dall'ex repo `terminal-agent-analysis`
(ora unificato qui). La documentazione corrente e canonica dell'app vive in `docs/` (un livello
sopra). In caso di conflitto, valgono i doc canonici.

Attenzione: la cartella **non è tutta storica**. Due file sono vivi e si aggiornano col codice, il
resto è archivio della fase di analisi.

## Vivi

- **`CYCLES.md`** - il diario decisionale, un'entrata per ciclo di lavoro. Parte dal Cycle 0
  (analisi engine, diagnosi lag cmux, benchmark) e continua a crescere: è il posto dove finisce il
  "perché" di ogni giro. Tiene gli ultimi ~15 cicli; i più vecchi ruotano in
  `cycles-archive/`, numerazione intatta. Linkato da `CLAUDE.md` e dal README come riferimento
  corrente.
- **`PERF.md`** - le misure di performance dietro ai budget di `../ARCHITECTURE.md` e la taratura
  del cap LRU, con le istruzioni per rieseguirle (`RELAY_PERF=1`).

## Archivio della fase di analisi

- **`REPORT.md`** - report iniziale di ricerca (Fase 0): confronto Otty/cmux/ghostty, tesi di
  prodotto, prime decisioni. Le valutazioni di licenza qui dentro (l'ipotesi di partire da una base
  GPL) sono superate: Relay è MIT e l'engine è SwiftTerm, MIT. Vedi `../../LICENSE`.
- **`ARCHITECTURE.md`** - architettura della fase di ricerca (Fase 0-1). Superata da
  `../ARCHITECTURE.md` (corrente), tenuta come storia del "perché".
- **`ROADMAP.md`** - piano di ricerca per fasi (0-1). Il piano forward attivo è `../ROADMAP.md`.
- **`spikes/`** - esperimenti di validazione:
  - `ourterm-spike/` - validazione della pipeline hook Claude -> stato (Cycle 1), poi portata
    nell'app in Milestone 1.
  - `swiftterm-spike/` - benchmark di throughput di SwiftTerm (Cycle 5). È un package SwiftPM a sé
    (non interferisce col build di relay); `docs/research` è escluso da lint/format.
