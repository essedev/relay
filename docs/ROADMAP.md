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

## Da chiudere subito: il teardown non termina niente

Non è una feature, è un bug di correttezza misurato (numeri e metodo in
`docs/research/PERF.md`, sezione sul leak). Chiudere una tab, un pane o un workspace lascia vivi la
shell, l'eventuale agente col suo albero MCP e il descrittore primario della pty, per sempre finché Relay non
muore. Vale anche per una tab con la shell ferma al prompt, e vale per lo sfratto LRU. L'alert di
conferma promette "will be terminated" e oggi è falso.

1. **Hangup esplicito della sessione pty** nel teardown: SIGHUP al process group in foreground e a
   quello della shell, poi `terminate()`, poi escalation a SIGKILL sui superstiti e `waitpid` (oggi
   le shell che muoiono restano zombie). Con l'invariante scritta: **una tab possiede la sessione
   POSIX della sua pty**, che è il criterio per `nohup`, `disown` e `setsid`.
2. **Test di regressione**: `FakeEngine` non vede il teardown, serve un test che apra e chiuda pty
   vere e verifichi fd, processi e zombie a zero. È il buco che ha lasciato passare questo.
3. **PR upstream a SwiftTerm**: `LocalProcess.terminate()` chiude la `DispatchIO` senza `.stop`, la
   read pendente sul descrittore primario non completa mai e il cleanup handler non chiude l'fd; in più
   `childStopped()` cancella il `DispatchSourceProcess` che avrebbe fatto `waitpid`. Quando la patch
   è mergiata e il pin aggiornato, il fix locale si riduce alla sola escalation (rete di sicurezza
   per i processi che ignorano SIGHUP).

## Disattivazione delle sessioni agente

Il cap LRU non sfratta mai una tab con un agente vivo (scelta deliberata, Cycle 9 e 15), quindi con
decine di sessioni la registry sta stabilmente a 3x il cap e la memoria è quella degli agenti, non
delle surface: ~200 MB e ~9 processi per sessione contro 0,3-0,5 MB per surface idle. Il cap è
tarato sull'unità di misura sbagliata per questo problema e **non va esteso**.

La strada, in due passi:

1. **Disattivazione esplicita**: azione su una tab, su un workspace o su una selezione della
   dashboard, con preview di cosa si interrompe. Uccide la sessione e tiene il `ResumeBinding`; al
   focus la `ResumeBar` la rimette in piedi. Due cose da chiudere: uccidere l'agente fa scattare il
   suo `SessionEnd`, che azzera il `resume` da cui la disattivazione dipende, e la soppressione va
   legata all'**istanza** del processo (non alla tab, o un evento in ritardo colpisce una sessione
   già ripartita); e una tab disattivata non deve riaccendersi da sola, perché `autoResumeAgents`
   esiste per il riavvio, che è involontario, mentre una disattivazione è voluta e il suo resume
   deve restare deliberato.
2. **Automatismo**, per ultimo e non a tempo: ammissibilità (binding coerente con l'istanza viva,
   nessun lavoro accessorio non classificabile), necessità (pressione di memoria sostenuta),
   priorità (lì sì, tempo dall'ultima interazione), con isteresi. `idle` è un prerequisito, non
   un'autorizzazione: nella stessa tab può girare un dev server.

Il nome è "disattiva", non "iberna": ibernare promette una continuità di stato che `--resume` non dà.

**Scartato: salvare il transcript al teardown.** Sembrava il passo abilitante (disattivare senza
perdere il verbale del lavoro), ma la conversazione è già persistita due volte fuori da Relay: il
resume la rimostra, e il record completo sta nei file di sessione dell'agente. Le tab senza agente
perdono già lo scrollback a ogni sfratto LRU, quindi la disattivazione non introduce una perdita
nuova. In più scrivere il buffer di un terminale su disco mette a riposo token, dump di env e URL
con credenziali: è una decisione di sicurezza, e qui non la ripaga niente. Resta vero solo il
vincolo che leggere una tab disattivata non deve riaccenderla, che è un marker sulla tab.

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
