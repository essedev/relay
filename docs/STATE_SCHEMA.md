# State Schema

Relay non usa un database in v1. Lo "schema" sono due cose: il **protocollo eventi agente**
(runtime, in memoria + socket) e lo **snapshot di persistence** (layout su disco). Questo file va
aggiornato nello stesso commit di ogni cambiamento a questi formati.

## Protocollo Eventi Agente (v1)

Trasporto: Unix domain socket, JSON lines. Fonte autorevole: hook Claude Code.
Tipi in `Sources/AgentProtocol/`.

Tipi evento (`AgentEventType`):

- `agent.session.start`
- `agent.state`
- `agent.notification`
- `agent.resume.set`
- `agent.session.end`

Stati normalizzati (`AgentState`): `running`, `idle`, `needs_input`, `error`, `unknown`.

Mapping Claude -> stato:

| Claude event | Stato |
| --- | --- |
| `SessionStart` | `idle` |
| `UserPromptSubmit` | `running` |
| `PreToolUse` | `running` |
| `PostToolUse` | `running` |
| `PermissionRequest` | `needs_input` |
| `Stop` | `idle` |

Esempio `agent.state` (`AgentStateEvent`):

```json
{
  "agent": "claude",
  "sessionId": "abc",
  "paneId": "pane-1",
  "state": "needs_input",
  "source": "hook",
  "confidence": 1,
  "timestamp": "2026-07-02T08:45:48Z"
}
```

Vietato nel payload persistito: prompt utente, token, chiavi, credenziali, contesto sensibile.

## Snapshot Di Persistence (layout)

Formato: JSON su disco (percorso da definire in Fase 5). Al restore tutti i pane nascono
`unrealized` (nessuna surface finché non c'è focus).

Entità (model in `Sources/WorkspaceModel/`):

```text
Workspace    { id, name, rootPath, pinned, sortIndex }
Tab          { id, workspaceId, title, sortIndex, paneTree }   // da aggiungere
Pane         { id, tabId, cwd, agentSessionId? }               // da aggiungere
Resume       { sessionId, agent, cwd, sanitizedCommand }       // da aggiungere
```

Resume: solo `sessionId`, `agent`, `cwd`, comando sanitizzato (`claude --resume <sessionId>`).

## Stato

Definito e in codice: `AgentState`, `AgentEventType`, `AgentStateEvent`, `Workspace`.
Da aggiungere quando servono: gerarchia Tab/Pane, resume, formato snapshot su disco.
