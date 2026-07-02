#!/usr/bin/env python3
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_kv(args: list[str]) -> dict[str, str]:
    out: dict[str, str] = {}
    for token in args:
        if "=" not in token:
            continue
        key, value = token.split("=", 1)
        out[key.strip()] = value.strip()
    return out


def load_state(path: Path) -> dict:
    if not path.exists():
        return {"sessions": {}}
    try:
        return json.loads(path.read_text())
    except Exception:
        return {"sessions": {}}


def load_events(path: Path) -> list[dict]:
    if not path.exists():
        return []
    events: list[dict] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except Exception:
            continue
    return events


def save_state(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True))


def handle_state_claude(path: Path, params: dict[str, str]) -> int:
    session_id = params.get("session-id")
    state = params.get("state")
    if not session_id or not state:
        print("missing required params: session-id, state", file=sys.stderr)
        return 2

    data = load_state(path)
    sessions = data.setdefault("sessions", {})
    current = sessions.get(session_id, {})

    updated = {
        "agent": "claude",
        "sessionId": session_id,
        "state": state,
        "bypass": params.get("bypass", "0") == "1",
        "source": "hook",
        "updatedAt": utc_now(),
    }

    if "context-b64" in params:
        updated["contextB64"] = params["context-b64"]

    if "pid" in params:
        updated["pid"] = params["pid"]

    if "turn-id" in params:
        updated["turnId"] = params["turn-id"]

    current.update(updated)
    sessions[session_id] = current
    save_state(path, data)
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: ourterm-state.py <command> [key=value ...]", file=sys.stderr)
        return 2

    state_file = Path(
        os.environ.get(
            "OURTERM_STATE_FILE",
            "/Users/doppia/Development/Yellow/terminal-agent-analysis/ourterm-spike/state/agent-states.json",
        )
    )
    log_file = Path(
        os.environ.get(
            "OURTERM_STATE_LOG_FILE",
            "/Users/doppia/Development/Yellow/terminal-agent-analysis/ourterm-spike/state/agent-state-events.jsonl",
        )
    )

    command = sys.argv[1]
    params = parse_kv(sys.argv[2:])

    if command == "state:claude":
        return handle_state_claude(state_file, params)

    if command == "dump":
        print(json.dumps(load_state(state_file), indent=2, sort_keys=True))
        return 0

    if command == "timeline":
        session_id = params.get("session-id") if params else None
        if not session_id and len(sys.argv) >= 3 and "=" not in sys.argv[2]:
            session_id = sys.argv[2].strip()
        if not session_id:
            print("usage: ourterm-state.py timeline <session-id>", file=sys.stderr)
            return 2

        events = [ev for ev in load_events(log_file) if ev.get("sessionId") == session_id]
        events.sort(key=lambda ev: ev.get("timestamp", ""))
        print(json.dumps({"sessionId": session_id, "events": events}, indent=2, sort_keys=True))
        return 0

    print(f"unknown command: {command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
