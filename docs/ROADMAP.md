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
prima classe (0.17.0).

## Prossimo giro (a scelta)

Nessuno dei tre è iniziato; si prende quello che serve per primo.

1. **Distribuzione firmata**: Developer ID + notarizzazione. Toglie l'"Apri comunque" e apre a
   homebrew-cask ufficiale. Il tap non firmato regge intanto. Vedi `docs/features/distribution.md`.
2. **Generalizzazione multi-agente** (Codex, opencode): il piano è qui sotto.
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

Prevista by design fin dall'inizio (tesi di prodotto: "molti coding agent", non "molte sessioni
Claude"; il protocollo resta aperto, `ARCHITECTURE.md` #Fonti-Stato e #Fuori-Scope-Baseline). Non
ancora pianificata come lavoro: qui il piano.

Stato del codice (misurato): il **core è già agnostico** - il wire ha il campo `agent`, gli stati
sono normalizzati, il reducer e `ResumeBinding` non conoscono Claude. La Claude-centricità è
**confinata** a `HookInstaller/ClaudeHookInstaller.swift`, il comando `relay-cli claude-hook`
(`ClaudeHookCommand`), il comando di resume (`claude --resume <id>`) e alcune stringhe UI
(NotificationCoordinator, AppController, ResumeBar, SettingsView). Il boundary progettuale è già nel
posto giusto.

Cosa espone ogni agente (verificato luglio 2026): **Codex** ha hook con nomi di evento quasi
identici a Claude (`PreToolUse`, `PermissionRequest`, `PostToolUse`, `SessionStart`, `Stop`,
`UserPromptSubmit`, `SubagentStop`) via `hooks.json` o `[hooks]` in `config.toml` - stesso paradigma,
cambia solo il vettore di installazione. Da rimappare per ognuno anche l'**errore**: su Claude è
`StopFailure` (Cycle 22), e un agente senza un evento equivalente lascerebbe il buco che avevamo
qui - la tab bloccata su `running` a turno morto. **opencode** espone un event bus (`session.created`,
`session.idle`, permission events) consumato da un plugin TS - segnali chiari, vettore diverso (un
plugin che scrive sul socket, non un hook shell).

Piano in tre passi, quando si apre il giro:

1. **Spike di verifica per agente**: cosa espone ognuno e quanto è affidabile il segnale, in
   particolare `needs_input` (le approval mode variano tra agenti). Non solo Codex/opencode: mappare
   il modello reale, non assumerlo.
2. **Refactor `AgentIntegration` + Codex insieme**: estrarre l'astrazione **mentre** si aggiunge il
   secondo agente (regola di due), non prima. Astrarre su un solo esempio ripete la trappola
   "interfaccia modellata troppo intorno a un backend" già nota per `TerminalEngine`. Codex prima
   perché il paradigma hook è quasi identico (mapping quasi copia-incolla, cambia il vettore).
3. **opencode come secondo banco di prova** del boundary (plugin TS -> socket). È il modello più
   diverso: se l'astrazione regge qui, regge.

Rischio da tenere in conto: il differenziatore ("stati affidabili senza parsing output") vale finché
ogni agente dà un segnale altrettanto affidabile; N integrazioni = N pipeline che evolvono e si
rompono. **Resta fuori scope** l'orchestrazione multi-agent nella stessa sessione (cosa diversa dal
supportare più agenti; `ARCHITECTURE.md` #Fuori-Scope-Baseline).
