#!/bin/sh
# ourterm Claude hook adapter
# Args:
#   $1 state: processing | idle | awaiting
#   $2 claude pid ($PPID from hook call site)
#   $3 "ctx" optional for PermissionRequest payload

state="$1"
claude_pid="$2"
want_ctx="$3"

input="$(cat)"
sid="${CLAUDE_SESSION_ID:-$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | sed -n '1p')}"

bypass=0
ps -o args= -p "$claude_pid" 2>/dev/null | grep -qF -- '--dangerously-skip-permissions' && bypass=1

cli="${OURTERM_CLI:-/Users/doppia/Development/Yellow/terminal-agent-analysis/ourterm-spike/bin/ourterm-state.py}"
log_cli="${OURTERM_LOG_CLI:-/Users/doppia/Development/Yellow/terminal-agent-analysis/ourterm-spike/bin/ourterm-state-log.py}"

if [ "$want_ctx" = "ctx" ]; then
    ctx="$(printf '%s' "$input" | base64)"
    "$cli" state:claude session-id="$sid" state="$state" bypass="$bypass" pid="$claude_pid" context-b64="$ctx" 2>/dev/null &
    "$log_cli" state:claude session-id="$sid" state="$state" bypass="$bypass" pid="$claude_pid" context-b64="$ctx" 2>/dev/null &
else
    "$cli" state:claude session-id="$sid" state="$state" bypass="$bypass" pid="$claude_pid" 2>/dev/null &
    "$log_cli" state:claude session-id="$sid" state="$state" bypass="$bypass" pid="$claude_pid" 2>/dev/null &
fi
