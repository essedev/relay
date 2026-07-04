# State Schema

Relay non usa un database in v1. Lo "schema" sono due cose: il **protocollo eventi agente**
(runtime, in memoria + socket) e lo **snapshot di persistence** (layout su disco). Questo file va
aggiornato nello stesso commit di ogni cambiamento a questi formati.

## Protocollo Eventi Agente (v1)

Trasporto: Unix domain socket, JSON lines. Fonte autorevole: hook Claude Code.
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
CLI (`relay-cli claude-hook`) fa da client. Vedi `RelayRuntimePaths`, `AgentEventReceiver`,
`AgentEventClient`.

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
| `SessionEnd` | `unknown` | - |

Il `matcher` esiste solo per gli eventi tool. `SubagentStop` non è mappato di proposito: lo stop di
un subagent non è il completamento del pane principale (anti-rumore).

**Tool a prompt bloccante**: il `PreToolUse` di `AskUserQuestion` e `ExitPlanMode` viene corretto
in `needs_input` dal CLI (`ClaudeHookStateMapper`, che legge `hook_event_name` e `tool_name` dallo
stdin dell'hook): quei tool non passano da `PermissionRequest` (non sono permessi) e non producono
`Stop` finché l'utente non risponde; il `PostToolUse`, che arriva solo dopo la risposta, riporta
`running`.

**Ri-presa attiva (`resetsAttention`)**: `SessionStart` porta un `source` (`startup`/`resume`/
`clear`/`compact`). Su `clear` (= `/clear`, `/new`) e `resume` il CLI lo legge dallo stdin e marca
l'evento `resetsAttention: true`: lo `state` resta `idle` (l'agente è fermo in attesa) ma il marker
di attenzione in sospeso si spegne, come farebbe il primo prompt. `startup`/`compact` restano `idle`
neutro. Il campo `source` esiste solo sul SessionStart, quindi discrimina da uno `Stop` idle.

**Binding sessione -> pane**: `RELAY_TAB_ID` (= `Tab.id`) è iniettato nell'ambiente della surface;
lo ereditano shell -> agent -> hook, e il CLI lo rimanda come `paneId`. Nessun parsing dell'output.

Esempio `agent.state` (`AgentStateEvent`, esattamente ciò che passa sul socket):

```json
{
  "agent": "claude",
  "sessionId": "abc",
  "paneId": "11111111-2222-3333-4444-555555555555",
  "state": "needs_input",
  "source": "hook",
  "confidence": 1,
  "timestamp": "2026-07-02T08:45:48.123Z"
}
```

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

Entità (`LayoutSnapshot` in `Sources/WorkspaceModel/`, `Codable`, versionato - bump di
`currentVersion` **solo per cambi breaking**: la load scarta le versioni diverse; un campo nuovo
opzionale è additivo e non bumpa):

```text
LayoutSnapshot    { version, selectedWorkspaceID?, workspaces: [WorkspaceSnapshot] }
WorkspaceSnapshot { id, name, rootPath?, pinned, selectedTabID?, tabs: [TabSnapshot] }
TabSnapshot       { id, title, hasCustomTitle, currentDirectory?, resume?, pendingSince? }
ResumeBinding     { agent, sessionId, label }
```

L'ordine dei workspace è l'ordine dell'array (riordinabile). `Tab.currentDirectory` è la cwd
riportata dalla shell via OSC 7 (alimenta titolo, sottotitolo e l'ereditarietà cwd di `Cmd+T`). Lo
stato agente (`agentState`/`lastEventAt`) è runtime e non si persiste, con due eccezioni mirate:
`resume` (la sessione ripristinabile: alimenta la ResumeBar al primo focus post-restore) e
`pendingSince` (il completamento "in sospeso" e la sua età; al restore anche `unseen` degrada a
`pending`, il segnale forte sarebbe stantio). Le surface del terminale NON sono nel model: sono
legate per `Tab.id` a runtime.

Resume: solo `agent`, `sessionId`, `label` (titolo della tab alla cattura). Il comando è derivato
(`\(agent) --resume <sessionId>`), mai persistito. Vietato: prompt, token, credenziali.

## Preferenze (UserDefaults)

Distinte dallo snapshot del layout: `AppSettings` (`Sources/WorkspaceModel/`) persiste in
`UserDefaults` (chiavi `relay.*`) tema, font family/size, cursore, sidebar
(collapsed + width), preferenze notifiche, keybindings rimappati, `autoResumeAgents` e la
decadenza dei sospesi (`pendingDecayHours`). Sono *preferenze* utente, non stato di sessione - per
quello UserDefaults è il posto giusto. Font e cursore sono sovrapposti al tema base
(`RelayTheme.withFontSize` / `withCursorBlink`), così il terminale li applica insieme al resto
della palette. L'elenco canonico è `AppSettings` stesso: questo paragrafo dice solo dove vivono.

## Stato

In codice: `AgentState`, `AgentEventType`, `AgentStateEvent`, `WorkspaceStore`, `Workspace`, `Tab`,
`AppSettings`, agent runtime completo (receiver/client/coordinator/reducer), persistence layout
(`LayoutSnapshot` + `LayoutStore` + `LayoutAutosave`) e resume (`ResumeBinding` + ResumeBar).
Da aggiungere quando serve: split (pane tree in `Tab`).
