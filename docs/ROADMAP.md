# Roadmap

Piano forward dell'app Relay: cosa manca e in che ordine. La storia (cicli chiusi, milestone
consegnate, analisi engine e benchmark) vive in `docs/research/CYCLES.md`; i dettagli di design in
`ARCHITECTURE.md` e in `docs/features/*.md`. Qui non si accumula: una milestone chiusa esce da
questo file.

## Dove siamo

Baseline chiuso e app **distribuita via Homebrew tap**
(`brew install --cask essedev/relay/relay-terminal`): agent runtime + badge, attenzione a tre
livelli con dashboard di triage, persistence del layout, cap LRU delle surface, bundle `.app` con
notifiche, gruppi in sidebar, nomina automatica dei workspace, guida in-app, **split v2 sul modello
cmux** (i pane ospitano le tab, una strip per pane), **multi-window** e gli errori API come stato di
prima classe per Claude Code (0.17.0). La 0.19.0 aggiunge Codex tramite hook nativi, con setup,
notifiche e resume dedicati; il limite sugli errori API Codex è descritto sotto.

## Prossimo giro (a scelta)

Nessuno dei tre è iniziato; si prende quello che serve per primo.

1. **Distribuzione firmata**: Developer ID + notarizzazione. Toglie l'"Apri comunque" e apre a
   homebrew-cask ufficiale. Il tap non firmato regge intanto. Vedi `docs/features/distribution.md`.
2. **Terzo agente** (opencode): il piano è qui sotto.
3. **Drag di tab fra pane** (incluso l'edge-drop stile bonsplit per creare uno split trascinando) e
   **drag di workspace fra finestre**: oggi una tab si sposta col menu contestuale e con lo
   shortcut, il drag riordina solo dentro la strip.

## Più avanti

- Dashboard oltre le due viste attuali: azioni inline (resume/chiudi) sulle card, contatore
  aggregato nell'header del pannello (quelli per corsia nel kanban ci sono già), preview delle
  ultime righe (richiede surface vive).
- Zoom del pane ed equalize dei divider.
- Rename del workspace dalla menu bar (oggi solo dal contestuale della sidebar).
- Altri hook Claude Code non ancora sfruttati: il set è cresciuto molto dal mapping v1
  (`PermissionDenied`, `Notification` con matcher `idle_prompt`, `SubagentStart`, `PostCompact`,
  `PreModelSwitch`, `CwdChanged`). Nessuno urgente, `StopFailure` era l'unico che copriva un buco
  vero, ma la lista va ripassata quando si tocca il mapping.
- Export della timeline degli eventi agente; import di temi da config Ghostty.

## Generalizzazione multi-agente

Claude Code e Codex sono integrati tramite hook nativi sopra lo stesso wire normalizzato. Gli
installer condividono trasformazioni JSON, backup e scrittura atomica; UI, notifiche e resume
scelgono l'agente della sessione. Rimane un limite upstream: Codex non espone un hook equivalente a
`StopFailure`, quindi Relay non può distinguere un errore API Codex senza interpretare l'output (che
resta deliberatamente fuori dal modello affidabile).

Prossimo banco di prova: **opencode**, che espone un event bus consumato da un plugin TypeScript
anziché hook shell. Se il boundary regge un vettore così diverso, l'astrazione multi-agente è
confermata. Resta fuori scope l'orchestrazione multi-agent nella stessa sessione.
