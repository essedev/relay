# Roadmap

> Nota: da Fase 2 in poi lo sviluppo vive nel repo `relay` (github.com/essedev/relay) e il piano
> forward attivo è in `../ROADMAP.md`. Questo file resta come piano di ricerca storico
> (Fase 0-1) e mappa delle fasi. Lo stato dei cicli è in `CYCLES.md` (fino a Cycle 7).

## Direzione

Costruire una nuova app macOS nativa, veloce e curata, per lavorare con molti coding agent in
parallelo: gli stati agente affidabili di Otty più l'organizzazione a workspace di cmux
(progetti in sidebar, pin, riordino, dashboard overview), senza il peso e il lag di cmux.

Scelte fondanti (dettagli in `ARCHITECTURE.md`):

- nuova app, non fork di `cmux`;
- engine terminale `libghostty` / `GhosttyKit`;
- UI macOS nativa: sidebar workspace, tab verticali, split pane, dashboard;
- stati agente via hook Claude Code, mai parsing dell'output;
- performance by design: lazy surface, budget renderer, sidebar disaccoppiata.

## Principi Di Prodotto

- Veloce: latenza input e budget di risorse hanno priorità su ogni feature.
- Organizzato: workspace, pin, riordino e dashboard risolvono il problema dei molti progetti
  con agenti in parallelo.
- Affidabile: gli stati agente arrivano da hook autorevoli.
- Piccolo: niente browser, cloud, iOS, remote tmux, marketplace nel baseline.

## Fase 0 - Ricerca E Decisione

Stato: completata (Cycle 0-3).

Output: `REPORT.md`, `spikes/ourterm-spike/`, `ARCHITECTURE.md`, diagnosi lag cmux, hook Claude
installati in parallelo a Otty.

Decisioni prese:

- `cmux` non è la base da forkare; è reference di prodotto e catalogo di anti-pattern.
- `libghostty` / `GhosttyKit` è il candidato engine principale.
- Gli hook Claude Code sono fondativi per gli stati agente.
- Il lag di cmux è architetturale (priming eager, SwiftUI monolitico), non dell'engine.

## Fase 1 - Spike Engine SwiftTerm

Stato: sostanzialmente completa. Engine deciso (Cycle 5): SwiftTerm v1 dietro `TerminalEngine`,
libghostty backend futuro. Spike funzionante + benchmark in `spikes/swiftterm-spike/`: build liscia col
toolchain standard, throughput ampiamente sufficiente. Rimandate alla Fase 2 (serve l'app
multi-surface): latenza input p99 e memoria incrementale per surface. Motivazione e numeri in
`ARCHITECTURE.md` e `CYCLES.md` (Cycle 5).

Obiettivo: validare che una shell macOS minima sopra SwiftTerm sia pratica e reattiva, con
toolchain standard (no zig, no binari di terzi).

Task:

1. Progetto SwiftPM eseguibile AppKit con dipendenza SwiftTerm.
2. App di prova: una finestra, una `LocalProcessTerminalView`, input tastiera, shell locale.
3. Misurare: latenza input percepita/strumentata, tempo di creazione della view (rilevante per
   lo switch lazy), memoria per surface con scrollback pieno.
4. Verificare le capacità che ci servono dietro `TerminalEngine`: dimensioni/resize, titolo,
   cwd, output/bell/OSC, scrollback cap; annotare cosa manca o va aggirato.

Exit criteria:

- surface visibile e interattiva in finestra macOS con `swift build`;
- misure raccolte e confrontate con i budget di `ARCHITECTURE.md`;
- setup, tempi di build e limiti di SwiftTerm documentati;
- bozza dell'interfaccia `TerminalEngine` derivata da ciò che serve davvero.

Timebox: 1-2 giorni (la build ora è liscia). Se SwiftTerm mostrasse un limite bloccante sui
budget, si rivaluta libghostty dietro la stessa astrazione.

## Fase 2 - Skeleton App

Stato: V0 (Cycle 6) + agent runtime/badge (Cycle 7, Milestone 1) + giro UI/UX e tooling (Cycle 8)
costruiti nel repo `relay` (github.com/essedev/relay). Fatto: struttura modulare + CI, engine
SwiftTerm vivo, app Workspace -> Tab -> terminale, agent-aware via hook (badge su tab/sidebar),
sistema di temi + chrome finestra + toggle sidebar + titolo contestuale, tooling demo/simulatore.
Rimandati: cap LRU, split, persistence del layout, misure latenza/memoria. Dettagli e piano forward
in `../ROADMAP.md` e `../ARCHITECTURE.md`.

Obiettivo: primo progetto reale dell'app.

Task:

1. Scegliere nome e creare repo con la struttura a package SwiftPM di `ARCHITECTURE.md`,
   Makefile, SwiftLint/SwiftFormat e CI attivi dal primo commit (`CONVENTIONS.md`).
2. App AppKit; SwiftUI solo nei pannelli isolati (vedi confine in `ARCHITECTURE.md`).
3. Workspace model: workspace/tab/pane store, ordinamento, pin, con unit test.
4. Terminal surface per pane con lifecycle lazy (`unrealized` -> `live`), un pane per
   cominciare, poi split destra/sotto e tab verticali.
5. Sidebar v0: lista workspace, selezione, pin, drag per riordinare.
6. Config iniziale: font/tema propri semplici (import da Ghostty config solo se pratico più
   avanti).

Exit criteria:

- più workspace con più sessioni terminale;
- split e focus funzionano;
- i pane dei workspace non visitati restano `unrealized` (verificato);
- `make check` verde in CI, moduli e limiti file rispettati;
- usabile come terminale quotidiano minimale.

## Fase 3 - Agent State Runtime

Obiettivo: portare `spikes/ourterm-spike` dentro l'app reale.

Task:

1. Unix socket + protocollo JSON lines al posto del file store.
2. Eventi v1: `agent.session.start`, `agent.state`, `agent.notification`, `agent.resume.set`,
   `agent.session.end`.
3. Mapping Claude -> stati prodotto (`running`, `needs_input`, `idle`).
4. Binding sessione -> pane via env iniettata.
5. Badge: pane, tab, workspace in sidebar, con aggregazione per severità.
6. Timeline debug.

Exit criteria:

- una sessione Claude reale aggiorna la UI senza parsing output;
- stato legato al pane corretto;
- `needs_input` genera attention visibile e notifica;
- un aggiornamento di badge non invalida il view tree del terminale (verificato).

## Fase 4 - Hook Installer

Obiettivo: integrazione installabile e reversibile.

Task:

1. CLI: `ourterm hooks setup|uninstall|status claude`, `ourterm state:claude ...`.
2. Install in `~/.claude/settings.json`: preservare esistenti, niente duplicati, backup,
   validazione JSON prima e dopo.
3. Hook adapter firmato e distribuito con l'app.
4. Sicurezza: niente token persistiti, context base64 solo quando serve, sanitizzazione log e
   resume.

Exit criteria:

- setup/uninstall ripetibile;
- non rompe Otty né hook utente;
- nuova sessione Claude funziona dopo l'installazione.

## Fase 5 - UX Prodotto

Obiettivo: rendere l'app bella e completa per l'uso quotidiano.

Task:

1. Dashboard overview v1: griglia workspace con stato agenti, ultimo evento, jump-to al click.
2. Sidebar refinement: stato agente, cwd, branch git, ultimo evento.
3. Notification design: notifica su `needs_input`, completed solo quando utile, dedupe e
   throttling.
4. Shortcut: new tab, split, focus pane, jump al più recente `needs_input`.
5. Session restore: layout, cwd, `claude --resume <session-id>` quando sicuro.
6. Performance pass: misurare contro i budget, niente invalidazioni durante il typing.

Exit criteria:

- una giornata intera di lavoro con più agenti senza attriti;
- budget di `ARCHITECTURE.md` rispettati con 10+ workspace aperti;
- notification noise accettabile.

## Fase 6 - Espansione Controllata

Candidati futuri (solo se servono davvero):

- hook Codex / plugin OpenCode;
- gruppi di workspace;
- watch command per attendere idle di una sessione;
- esportazione timeline;
- protocollo plugin minimo per altri agenti.

Non pianificati nel baseline: browser automation, iOS, cloud VM, presence/sync, remote tmux
avanzato, skill marketplace, hibernation, orchestrazione multi-agent complessa.

## Prossima Azione

Fase 1 su SwiftTerm:

1. progetto SwiftPM AppKit con dipendenza SwiftTerm;
2. prima finestra macOS con `LocalProcessTerminalView` e shell locale;
3. misure di latenza e bozza interfaccia `TerminalEngine`.
