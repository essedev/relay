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


def append_event(path: Path, params: dict[str, str]) -> int:
    session_id = params.get("session-id")
    state = params.get("state")
    if not session_id or not state:
        print("missing required params: session-id, state", file=sys.stderr)
        return 2

    event = {
        "timestamp": utc_now(),
        "agent": "claude",
        "sessionId": session_id,
        "state": state,
        "bypass": params.get("bypass", "0") == "1",
        "pid": params.get("pid"),
    }

    if "context-b64" in params:
        event["contextB64"] = params["context-b64"]

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(event, sort_keys=True) + "\n")
    return 0


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: ourterm-state-log.py state:claude key=value ...", file=sys.stderr)
        return 2

    if sys.argv[1] != "state:claude":
        print("unknown command", file=sys.stderr)
        return 2

    log_path = Path(
        os.environ.get(
            "OURTERM_STATE_LOG_FILE",
            "/Users/doppia/Development/Yellow/terminal-agent-analysis/ourterm-spike/state/agent-state-events.jsonl",
        )
    )
    params = parse_kv(sys.argv[2:])
    return append_event(log_path, params)


if __name__ == "__main__":
    raise SystemExit(main())
