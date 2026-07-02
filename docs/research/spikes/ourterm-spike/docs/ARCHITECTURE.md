# OurTerm Spike Architecture

## Goal

Validate an agent-state pipeline that is reliable and independent from terminal output heuristics.

## Layers

1. UI shell (future macOS app):
   - vertical tabs
   - split panes
   - sidebar with agent badges
2. Terminal engine (future):
   - libghostty / GhosttyKit
3. Agent-state pipeline (implemented in this spike):
   - Claude hooks -> hook adapter script -> `ourterm-state.py` receiver -> state file
4. Notification/badge mapping (future):
   - `processing` -> spinner/running badge
   - `awaiting` -> needs input badge + notification
   - `idle` -> completed/idle badge

## Why this shape

- Hook events are authoritative for agent lifecycle.
- OSC/output parsing is useful for generic shell commands but fragile for agent state.
- This allows UI and engine to evolve independently from agent integrations.

## Protocol (v0)

Command:

```text
ourterm-state.py state:claude session-id=<id> state=<processing|awaiting|idle> bypass=<0|1> [context-b64=<...>] [pid=<...>]
```

State file:

`ourterm-spike/state/agent-states.json`

Per-session record:

- `agent`
- `sessionId`
- `state`
- `bypass`
- `source`
- `updatedAt`
- optional `contextB64`
- optional `pid`

## Next step after spike

- Replace file-based store with local socket service.
- Add an in-app state observer and badge renderer.
- Add transition logic:
  - `processing -> awaiting` creates unread attention marker.
  - `awaiting -> idle` clears attention marker.
