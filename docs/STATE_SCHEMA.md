# State Schema

Relay non usa un database in v1. Lo "schema" sono due cose: il **protocollo eventi agente**
(runtime, in memoria + socket) e lo **snapshot di persistence** (layout su disco). Questo file va
aggiornato nello stesso commit di ogni cambiamento a questi formati.

## Protocollo Eventi Agente (v1)

Trasporto: Unix domain socket, JSON lines. Fonte autorevole: hook Claude Code.
Tipi in `Sources/AgentProtocol/`; trasporto in `Sources/AgentRuntime/`.

**Formato sul filo (v1)**: una riga = un `AgentStateEvent` codificato JSON (date ISO 8601). Non c'è
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
| `PreToolUse` | `running` | `*` |
| `PostToolUse` | `running` | `*` |
| `PermissionRequest` | `needs_input` | - |
| `Stop` | `idle` | - |
| `SessionEnd` | `unknown` | - |

Il `matcher` esiste solo per gli eventi tool. `SubagentStop` non è mappato di proposito: lo stop di
un subagent non è il completamento del pane principale (anti-rumore).

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
  "timestamp": "2026-07-02T08:45:48Z"
}
```

Vietato nel payload: prompt utente, token, chiavi, credenziali, contesto sensibile.

## Snapshot Di Persistence (layout)

Formato: JSON su disco (percorso da definire in Fase 5). Al restore tutti i pane nascono
`unrealized` (nessuna surface finché non c'è focus).

Entità (model in `Sources/WorkspaceModel/`):

```text
Workspace { id, name, rootPath?, pinned, tabs: [Tab], selectedTabID }        // in codice
Tab       { id, title, hasCustomTitle, currentDirectory?, agentState, ... }  // in codice
Resume    { sessionId, agent, cwd, sanitizedCommand }                        // da aggiungere
```

L'ordine dei workspace è l'ordine dell'array (riordinabile). `selectedWorkspaceID` sta nello
store. `Tab.currentDirectory` è la cwd riportata dalla shell via OSC 7 (alimenta titolo, sottotitolo
e l'ereditarietà cwd di `Cmd+T`). Lo stato agente (`agentState`/`attention`/`lastEventAt`) è runtime,
non va persistito. Le surface del terminale NON sono nel model: sono legate per `Tab.id` a runtime.

Resume: solo `sessionId`, `agent`, `cwd`, comando sanitizzato (`claude --resume <sessionId>`).

## Preferenze (UserDefaults)

Già implementate, distinte dallo snapshot del layout: `AppSettings` (`Sources/WorkspaceModel/`)
persiste `themeName`, `fontSize`, `cursorBlink`, `sidebarCollapsed` in `UserDefaults` (chiavi
`relay.*`). Sono *preferenze* utente, non stato di sessione - per quello UserDefaults è il posto
giusto. `fontSize` e `cursorBlink` sono sovrapposti al tema base (`RelayTheme.withFontSize` /
`withCursorBlink`), così il terminale li applica insieme al resto della palette.

## Stato

In codice: `AgentState`, `AgentEventType`, `AgentStateEvent`, `WorkspaceStore`, `Workspace`, `Tab`,
`AppSettings`, agent runtime completo (receiver/client/coordinator/reducer).
Da aggiungere quando servono: split (pane tree in `Tab`), resume, snapshot del layout su disco.
