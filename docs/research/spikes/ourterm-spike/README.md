# OurTerm Spike

> Spike storico del ciclo di ricerca: i path qui sotto sono placeholder, vanno adattati alla
> posizione reale della cartella `ourterm-spike` sulla tua macchina.

Minimal prototype to validate reliable Claude agent states via hooks.

## Files

- `bin/ourterm-state.py`: local receiver CLI (`state:claude`, `dump`)
- `bin/ourterm-claude-hook.sh`: Claude hook adapter script
- `docs/ARCHITECTURE.md`: spike architecture
- `docs/CLAUDE_HOOKS_SNIPPET.json`: settings snippet
- `state/agent-states.json`: runtime state store

## Quick test

```bash
/path/to/ourterm-spike/bin/ourterm-state.py state:claude session-id=test state=processing bypass=0
/path/to/ourterm-spike/bin/ourterm-state.py dump
/path/to/ourterm-spike/bin/ourterm-state.py timeline test
```

## Intended mapping

- `SessionStart` -> `idle`
- `UserPromptSubmit` -> `processing`
- `PreToolUse` -> `processing`
- `PostToolUse` -> `processing`
- `PermissionRequest` -> `awaiting`
- `Stop` -> `idle`
