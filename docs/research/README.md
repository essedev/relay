# Ricerca

Storia della ricerca che ha portato a Relay, importata dall'ex repo `terminal-agent-analysis`
(ora unificato qui). Materiale **storico**: la documentazione corrente e canonica dell'app vive in
`docs/` (un livello sopra). In caso di conflitto, valgono i doc canonici.

## Contenuto

- **`CYCLES.md`** - log dei cicli di lavoro (0-8): analisi engine, diagnosi lag cmux, benchmark,
  agent runtime, giro UI/UX. È il diario decisionale.
- **`REPORT.md`** - report iniziale di ricerca (Fase 0): confronto Otty/cmux/ghostty, tesi di
  prodotto, prime decisioni.
- **`ARCHITECTURE.md`** - architettura della fase di ricerca (Fase 0-1). Superata da
  `../ARCHITECTURE.md` (corrente), tenuta come storia del "perché".
- **`ROADMAP.md`** - piano di ricerca per fasi (0-1). Il piano forward attivo è `../ROADMAP.md`.
- **`spikes/`** - esperimenti di validazione:
  - `ourterm-spike/` - validazione della pipeline hook Claude -> stato (Cycle 1), poi portata
    nell'app in Milestone 1.
  - `swiftterm-spike/` - benchmark di throughput di SwiftTerm (Cycle 5). È un package SwiftPM a sé
    (non interferisce col build di relay); `docs/research` è escluso da lint/format.
