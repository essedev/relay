# State Schema

Relay non usa un database in v1. Lo "schema" sono due cose: il **protocollo eventi agente**
(runtime, in memoria + socket) e lo **snapshot di persistence** (layout su disco). Questo file va
aggiornato nello stesso commit di ogni cambiamento a questi formati.

## Protocollo Eventi Agente (v1)

Trasporto: Unix domain socket, JSON lines. Fonti autorevoli: hook Claude Code e Codex.
Tipi in `Sources/AgentProtocol/`; trasporto in `Sources/AgentRuntime/`.

**Formato sul filo (v1)**: una riga = un `AgentStateEvent` codificato JSON (date ISO 8601 **con
millisecondi**; il decode accetta anche il formato storico a secondi interi, ma un'app vecchia non
decodifica gli eventi di un CLI nuovo). Le frazioni servono alla guardia di monotonicità negli
store: gli hook sono processi concorrenti, il trasporto non garantisce l'ordine, e gli eventi più
vecchi dell'ultimo applicato per tab/sessione vengono scartati. Non c'è
ancora un envelope con `type`: in v1 ogni hook mappa a un `agent.state`, quindi il tipo è implicito.
`AgentEventType` (`agent.session.start/state/notification/resume.set/session.end`) resta definito per
quando serviranno payload diversi (session lifecycle, resume): allora si introduce l'envelope.

Percorso socket: `~/.relay/relay.sock` (override `RELAY_SOCKET`). Il receiver (app) fa da server; il
CLI (`relay-cli claude-hook` / `codex-hook`) fa da client. Vedi `RelayRuntimePaths`, `AgentEventReceiver`,
`AgentEventClient`. Il receiver non calpesta un socket vivo (una `connect` di prova prima del bind)
e si auto-rigenera (ri-binda se il file sparisce sotto di lui): senza, un socket cancellato da
un'altra istanza congelava tutti i badge. Dettaglio in `ARCHITECTURE.md`, Local Control API.

Stati normalizzati (`AgentState`): `running`, `idle`, `needs_input`, `error`, `unknown`.

Mapping Claude -> stato (installato in `settings.json` da `ClaudeHookInstaller`):

| Claude event | Stato | matcher |
| --- | --- | --- |
| `SessionStart` | `idle` | - |
| `UserPromptSubmit` | `running` | - |
| `PreToolUse` | `running` (`needs_input` se il tool apre un prompt, vedi sotto) | `*` |
| `PostToolUse` | `running` | `*` |
| `PermissionRequest` | `needs_input` | - |
| `Stop` | `idle` | - |
| `StopFailure` | `error` | - |
| `SessionEnd` | `unknown` | - |

Il `matcher` è obbligatorio solo per gli eventi tool, che senza non scattano. `StopFailure` lo
supporta (matcha sul tipo di errore) ma noi lo omettiamo di proposito: chiave assente equivale a
`"*"`, quindi **tutti** i tipi (`rate_limit`, `overloaded`, `authentication_failed`,
`oauth_org_not_allowed`, `account_on_hold`, `billing_error`, `invalid_request`, `model_not_found`,
`server_error`, `max_output_tokens`, `unknown`) collassano nello stesso stato `error`.

**`StopFailure` è l'unica fonte di `error`**: scatta quando il turno finisce per un errore API.
`Stop` copre solo la fine normale, quindi senza questo hook un turno morto non emette nulla e la
tab resta `running` per sempre. `SubagentStop` non è mappato di proposito (lo stop di un subagent
non è il completamento del pane principale), e nemmeno `PostToolUseFailure` (un tool che fallisce
dentro un turno che prosegue non è un errore di sessione).

`ClaudeHookInstaller.isInstalled` richiede che **tutti** gli spec di questa tabella siano presenti,
non almeno uno: quando la tabella cresce, un'installazione fatta da una versione precedente deve
risultare incompleta, o l'utente non riceverebbe mai il nuovo hook. Il setup è idempotente.

**Tool a prompt bloccante**: il `PreToolUse` di `AskUserQuestion` e `ExitPlanMode` viene corretto
in `needs_input` dal CLI (`ClaudeHookStateMapper`, che legge `hook_event_name` e `tool_name` dallo
stdin dell'hook): quei tool non passano da `PermissionRequest` (non sono permessi) e non producono
`Stop` finché l'utente non risponde; il `PostToolUse`, che arriva solo dopo la risposta, riporta
`running`.

Mapping Codex -> stato (installato in `~/.codex/hooks.json` da `CodexHookInstaller`):

| Codex event | Stato | matcher |
| --- | --- | --- |
| `SessionStart` | `idle` | - |
| `UserPromptSubmit` | `running` | - |
| `PreToolUse` | `running` (`needs_input` per `request_user_input`) | `*` |
| `PostToolUse` | `running` | `*` |
| `PermissionRequest` | `needs_input` | - |
| `Stop` | `idle` | - |
| `Interrupt` | `idle`, con `resetsAttention` | - |
| `SessionEnd` | `unknown` | - |

Codex non espone oggi un hook equivalente a `StopFailure`. Relay non deduce gli errori dall'output:
un errore API Codex resta quindi visibile nel terminale, ma non produce lo stato `error`. L'evento
`Interrupt` non è un completamento: `resetsAttention` impedisce marker e notifica falsi sulla
transizione `running -> idle`. Le configurazioni utente Codex vanno riviste con `/hooks` dopo il
setup e ogni modifica delle definizioni. Lo status dell'installer non verifica il trust.

**Attenzione, due `source` diversi con lo stesso nome**. Sul filo `source` è
l'`AgentStateSource` - **quanto è autorevole** lo stato: `hook`, `osc`, `shell_integration`,
`heuristic` (v1 manda sempre `hook`). Il `source` di cui parla il paragrafo qui sotto
(`startup`/`resume`/`clear`/`compact`) è un campo dello **stdin dell'hook** `SessionStart`:
il CLI lo legge e lo traduce in `resetsAttention`, ma non finisce mai sul filo.

**Ri-presa attiva (`resetsAttention`)**: sullo stdin di `SessionStart` l'agente passa un `source`
(`startup`/`resume`/`clear`/`compact`). Su `clear` (= `/clear`, `/new`) e `resume` il CLI lo legge e
marca l'evento `resetsAttention: true`: lo `state` resta `idle` (l'agente è fermo in attesa) ma il
marker di attenzione in sospeso si spegne, come farebbe il primo prompt. `startup` resta `idle`
neutro; `compact` non viene inviato affatto (vedi sotto).

**Binding sessione -> pane**: `RELAY_TAB_ID` (= `Tab.id`) è iniettato nell'ambiente della surface;
lo ereditano shell -> agent -> hook, e il CLI lo rimanda come `paneId`. Accanto viaggia
`RELAY_RUN_ID` (`Core.RelayRunID`, nonce per processo dell'app), che torna come `runId`. Nessun
parsing dell'output.

Esempio `agent.state` (`AgentStateEvent`, esattamente ciò che passa sul socket):

```json
{
  "agent": "claude",
  "sessionId": "abc",
  "paneId": "11111111-2222-3333-4444-555555555555",
  "runId": "A1B2C3D4",
  "state": "needs_input",
  "source": "hook",
  "confidence": 1,
  "timestamp": "2026-07-02T08:45:48.123Z",
  "resetsAttention": false
}
```

**`runId` non è opzionale in pratica**: lo store applica un **fence di run**
(`WorkspaceStore.runID`, `WorkspaceStore+AgentState.swift`) e scarta ogni evento il cui `runId` non
è quello della run corrente, **`nil` compreso**. Sul tipo il campo è opzionale solo per far
decodificare gli eventi di un CLI vecchio, che poi vengono comunque scartati: un `RELAY_TAB_ID` è
stabile tra i riavvii, quindi uno `Stop` o un `SessionEnd` di una sessione orfana sopravvissuta a un
restart azzererebbe un resume binding appena ripristinato. Chi produce eventi deve mandare il
`runId` che ha trovato nell'env della surface. Complementare al fence c'è `eventFloor` (soglia
anti-stantio timbrata all'avvio), che scarta gli eventi con timestamp anteriore al boot.

`resetsAttention` (default `false`, di solito omesso dai CLI vecchi) è `true` sui `SessionStart`
di `clear`/`resume` e su `Interrupt` Codex: ri-prese o interruzioni che non devono sembrare un
completamento. `sessionId` è vuoto quando
la sessione è sconosciuta (lo store salta il resume binding); un `SessionStart` con `source=compact`
non viene inviato affatto (rumore, fingerebbe un completamento).

Vietato nel payload: prompt utente, token, chiavi, credenziali, contesto sensibile.

## Snapshot Di Persistence (layout)

Formato: JSON atomico su disco, `~/.relay/layout.json` (override `RELAY_LAYOUT`; path iniettato in
`LayoutStore`). Salvataggio debounced via `LayoutAutosave`, restore al boot con fallback al seed
default se file mancante/corrotto/versione ignota. Al restore tutti i pane nascono `unrealized`
(nessuna surface finché non c'è focus).

Robustezza (il layout è dato utente non ricreabile a mano). Tre difese in `LayoutStore`:

- **Guardia anti-degrado**: `save` valida l'invariante (almeno un workspace, ogni workspace con
  almeno una tab - sempre vero a runtime per il cascade e `ensureAtLeastOneWorkspace`) e **rifiuta**
  (`degenerateSnapshot`) uno snapshot degradato invece di scriverlo. Un save "0 tab" è il sintomo di
  una race, non uno stato da persistere.
- **Backup rotazionale**: prima di sovrascrivere, `save` conserva il primario valido in
  `layout.json.bak`.
- **Recovery**: `load` ricade sul `.bak` se il primario è mancante/corrotto/degradato/di versione
  ignota.

Questo chiude il caso in cui il layout perdeva le tab: una singola scrittura degradata (o una race
di due istanze - vedi single-instance sotto) non cancella più l'ultimo layout buono.

Entità (`LayoutSnapshot` in `Sources/WorkspaceModel/`, `Codable`, versionato - `currentVersion` è
**1** dal primo giorno; bump **solo per cambi breaking**: la load scarta le versioni diverse; un
campo nuovo opzionale è additivo e non bumpa, ed è per questo che split, multi-window, archivio e
nomina automatica sono arrivati senza toccarla):

```text
LayoutSnapshot    { version, selectedWorkspaceID?, workspaces: [WorkspaceSnapshot],
                    windows: [WindowSnapshot], groups: [GroupSnapshot] }
WindowSnapshot    { id, selectedWorkspaceID?, frame?: WindowFrame, isKey }
WindowFrame       { x, y, width, height }
GroupSnapshot     { id, name, colorIndex, collapsed, pinned }
WorkspaceSnapshot { id, windowID, groupID?, name, nameOrigin, rootPath?, pinned, archived,
                    selectedTabID?, tabs: [TabSnapshot], splitLayout?: SplitNode,
                    focusedPaneID? }
TabSnapshot       { id, title, hasCustomTitle, currentDirectory?, resume?, pendingSince?,
                    deactivated }
ResumeBinding     { agent, sessionId, label }
SplitNode         = { pane: SplitPane } | { split: { id, axis, ratio, first, second } }
SplitPane         { id, tabIDs: [UUID], selectedTabID? }
```

Campi additivi e loro default all'assenza (tutti letti con `decodeIfPresent`, mai sintetizzati: una
chiave mancante farebbe fallire il decode, cioè butterebbe il layout dell'utente):

| Campo | Assente -> | Perché |
| --- | --- | --- |
| `windows` | `[]` (una finestra sola, `RelayWindow.mainID`) | layout pre multi-window |
| `windowID` | `RelayWindow.mainID` | idem |
| `groups` | `[]` (nessun gruppo, righe tutte libere) | layout pre gruppi |
| `groupID` | `nil` (workspace fuori da ogni gruppo) | idem |
| `nameOrigin` | `.user` | i nomi pre-feature sono dell'utente, non si rigenerano |
| `archived` | `false` | layout pre archivio |
| `splitLayout` | `nil` -> pane radice con tutte le tab | layout pre split |
| `focusedPaneID` | `nil` -> il pane della selezione | layout pre modello cmux |
| `pendingSince` | `nil` (nessun sospeso) | layout pre attenzione a tre livelli |
| `deactivated` | `false` (tab normale) | layout pre disattivazione delle sessioni |

I gruppi sono salvati come **solo aspetto** (nome, colore, collassato, pinnato): l'appartenenza vive
su `WorkspaceSnapshot.groupID`, quindi non c'è una lista di membri da validare al restore. Due
guardie al load (`WorkspaceStore+Persistence.swift:112` e `:121`): un workspace archiviato perde
l'appartenenza salvata (un archiviato non sta in una card), e i gruppi rimasti senza membri vengono
potati, perché un gruppo senza righe non ha una posizione in sidebar e quindi non esiste.

`splitLayout` e `focusedPaneID` sono tolleranti anche al **valore**, non solo alla chiave: un nodo
corrotto o di un formato futuro degrada a `nil` invece di far fallire il decode. Il `Codable` di
`SplitNode` accetta ancora le **foglie-tab del formato v1** (`{ "leaf": { "_0": <uuid> } }`, che
diventa un pane con quella sola tab); in scrittura esiste solo il formato a pane, quindi dal primo
save post-split-v2 il file **non è più leggibile** da un binario <= 0.8.2 (compat solo all'indietro:
un downgrade riparte dal seed). Al restore l'albero viene sanitizzato contro le tab davvero
ricostruite (`SplitNode.sanitized`): tab sparite o duplicate escono, i pane vuoti collassano, e le
tab fuori dall'albero vengono adottate dal pane radice. Invariante: una tab in **un pane solo**, ogni
pane con almeno una tab.

L'ordine dei workspace è l'ordine dell'array (riordinabile: lo muta il drag in sidebar **e** il bump
di attività, `bumpWorkspaceToTop`). `Tab.currentDirectory` è la cwd
riportata dalla shell via OSC 7 (alimenta titolo, sottotitolo e l'ereditarietà cwd di `Cmd+T`). Lo
stato agente (`agentState`/`lastEventAt`/`attentionSince`) è runtime e non si persiste, con due
eccezioni mirate: `resume` (la sessione ripristinabile: alimenta la ResumeBar al primo focus
post-restore) e `pendingSince` (il completamento "in sospeso"). Al restore anche `unseen` degrada a
`pending` (il segnale forte sarebbe stantio) e il clock della decadenza (`attentionSince`) riparte
dal boot, così un completamento mai visto non viene spazzato subito. Nota: `attentionSince` è il
clock del marker (distinto da `lastEventAt`, che avanza a ogni evento per la guardia di
monotonicità); guida la decadenza e l'età del sospeso, così un no-op non li falsifica. Le surface
del terminale NON sono nel model: sono legate per `Tab.id` a runtime.

Resume: solo `agent`, `sessionId`, `label` (titolo della tab alla cattura). Il comando è derivato
(`\(agent) --resume <sessionId>`), mai persistito. Vietato: prompt, token, credenziali.

### Single-instance

Due Relay sullo stesso `~/.relay` si pesterebbero: gli autosave corromperebbero il layout e i
receiver il socket. Tre difese: `LSMultipleInstancesProhibited` (Info.plist) blocca il doppio
lancio lato LaunchServices; un guard in `Relay.main` per bundle id attiva l'istanza esistente ed
esce (copre la finestra di un upgrade); un secondo guard sul path esce se un receiver vivo possiede
già il nostro socket (`AgentEventClient.isReceiverReachable`), a copertura dei lanci senza bundle id
(`swift run`) che il primo non intercetta. Istanze dev legittime usano `RELAY_SOCKET`/`RELAY_LAYOUT`
diversi. A livello di trasporto il no-stomp e il self-heal del receiver (vedi sopra) sono la rete
finale se un'istanza sfugge ai guard.

## Preferenze (UserDefaults)

Distinte dallo snapshot del layout: `AppSettings` (`Sources/WorkspaceModel/`) persiste in
`UserDefaults` (chiavi `relay.*`) tema, font family/size, cursore, sidebar
(collapsed + width + archivio espanso), preferenze notifiche, keybindings rimappati,
`autoResumeAgents`, il doppio click sulla strip che apre una tab
(`newTabOnStripDoubleClick`, default on), la decadenza dei sospesi (`pendingDecayHours`),
il check aggiornamenti
(`checkForUpdatesAutomatically` + `skippedUpdateVersion`), la vista della dashboard
(`dashboardLayout`: kanban o griglia), la configurazione **non segreta** della nomina automatica
(`workspaceNamingEnabled` + base URL + model) e il flag one-shot dell'onboarding
(`onboardingSeen`, timbrato alla prima presentazione del "Welcome to Relay"). Sono *preferenze*
utente, non stato di sessione - per
quello UserDefaults è il posto giusto. Font e cursore sono sovrapposti al tema base
(`RelayTheme.withFontSize` / `withCursorBlink`), così il terminale li applica insieme al resto
della palette. L'elenco canonico è `AppSettings` stesso: questo paragrafo dice solo dove vivono.

## Credenziali (file 0600)

Il terzo formato su disco, tenuto **fuori** da UserDefaults perché è un segreto:
`~/.relay/naming-credentials.json` (`NamingCredentialStore` nel composition root), JSON con la sola
API key dell'endpoint OpenAI-compatible della nomina automatica, scritto con permessi `0o600`. Base
URL e model, che non sono segreti, stanno in `AppSettings`. Mai loggata, mai nello snapshot del
layout, mai in un payload evento.

## Stato

In codice: `AgentState`, `AgentEventType`, `AgentStateEvent` (con fence di run), `WorkspaceStore`,
`Workspace`, `Tab`, `SplitNode`/`SplitPane`, `RelayWindow`, `AppSettings`, agent runtime completo
(receiver/client/coordinator/reducer), persistence layout (`LayoutSnapshot` + `LayoutStore` +
`LayoutAutosave`) con split, finestre, gruppi, archivio, `nameOrigin` e sospesi, e resume
(`ResumeBinding` + ResumeBar).

Non ancora nello snapshot: nulla di strutturale in sospeso. Le evoluzioni note (drag di tab fra
pane, drag di workspace fra finestre) muovono id dentro i formati già descritti qui e non ne
introducono di nuovi.
