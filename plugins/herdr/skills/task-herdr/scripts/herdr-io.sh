#!/usr/bin/env bash
# herdr-io.sh - idle-guarded I/O against a tracked herdr pane agent. Three
# subcommands make orchestrator<->tab interactions safe:
#
#   wait-idle  block until the pane's agent_status has been `idle` on N
#              CONSECUTIVE polls (a streak). herdr reports a sub-second `idle`
#              blip BETWEEN an agent's tool calls / thinking transitions, so a
#              single idle reading (e.g. `herdr wait agent-status --status idle`)
#              false-fires long before the agent has actually stopped at a gate.
#              Requiring a streak of consecutive idle reads filters those blips
#              and only returns on sustained idle.
#   send       relay a message to a tab agent. By DEFAULT it first runs the same
#              stable wait-idle, so we never type over a working agent (typing
#              into a working agent queues/garbles the input). --force skips the
#              wait and injects immediately - the sanctioned escape hatch for
#              deliberately interrupting/steering a working agent.
#   stop       deliberately interrupt a working agent by sending the stop key.
#              For a `claude` agent in a herdr pane the stop key is Escape (a
#              single Esc cancels the current turn); herdr maps the key name
#              `Escape` to the ESC byte. This is --force by definition.
#
# Usage:
#   herdr-io.sh wait-idle PANE [--interval N] [--streak N] [--timeout SEC] [--json]
#   herdr-io.sh send PANE (--text STR | --file PATH) [--force] [--no-enter]
#                         [--settle SEC] [--interval N] [--streak N] [--timeout SEC]
#   herdr-io.sh stop PANE [--wait]
#
# A pane's agent_status comes from `herdr pane get PANE` at
# `.result.pane.agent_status` (idle / working / blocked / unknown); a pane that
# is gone is treated as `missing`.
#
# Exit codes for wait-idle (and send's internal wait): 0 stable-idle reached,
# 1 timeout, 3 pane missing.
#
# Requires: herdr (HERDR_ENV=1), python3.
set -euo pipefail

die() { echo "herdr-io: $*" >&2; exit 1; }

[ "${HERDR_ENV:-}" = "1" ] || die "not inside herdr (HERDR_ENV != 1)"
command -v herdr   >/dev/null 2>&1 || die "herdr not on PATH"
command -v python3 >/dev/null 2>&1 || die "python3 not on PATH"

# agent_status for a pane, or "missing" if the pane is gone.
status_of() {
  herdr pane get "$1" 2>/dev/null | python3 -c '
import sys, json
try:
    p = json.load(sys.stdin)["result"]
    # pane get returns the pane object (directly or under "pane")
    p = p.get("pane", p)
    print(p.get("agent_status", "unknown"))
except Exception:
    print("missing")
' 2>/dev/null || echo "missing"
}

# Core stable-idle wait. Reads globals INTERVAL/STREAK/TIMEOUT; sets WAITED and
# FINAL_STREAK. Returns 0 (stable idle), 1 (timeout), 3 (pane missing). Prints
# nothing so callers (send, stop --wait) can wrap it.
WAITED=0; FINAL_STREAK=0
wait_idle_core() {
  local pane="$1" streak=0 start="$SECONDS" st elapsed
  while :; do
    st="$(status_of "$pane")"
    if [ "$st" = "missing" ]; then
      WAITED=$((SECONDS - start)); FINAL_STREAK=$streak; return 3
    fi
    if [ "$st" = "idle" ]; then streak=$((streak + 1)); else streak=0; fi
    if [ "$streak" -ge "$STREAK" ]; then
      WAITED=$((SECONDS - start)); FINAL_STREAK=$streak; return 0
    fi
    elapsed=$((SECONDS - start))
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
      WAITED=$elapsed; FINAL_STREAK=$streak; return 1
    fi
    sleep "$INTERVAL"
  done
}

cmd_wait_idle() {
  local pane="" json=0
  INTERVAL=5; STREAK=3; TIMEOUT=3600
  while [ $# -gt 0 ]; do
    case "$1" in
      --interval) INTERVAL="$2"; shift 2 ;;
      --streak)   STREAK="$2"; shift 2 ;;
      --timeout)  TIMEOUT="$2"; shift 2 ;;
      --json)     json=1; shift ;;
      -*)         die "wait-idle: unknown arg: $1" ;;
      *)          [ -z "$pane" ] || die "wait-idle: unexpected arg: $1"; pane="$1"; shift ;;
    esac
  done
  [ -n "$pane" ] || die "wait-idle: PANE is required"

  local rc=0; wait_idle_core "$pane" || rc=$?
  local result
  case "$rc" in
    0) result="idle" ;;
    1) result="timeout" ;;
    3) result="missing" ;;
  esac

  if [ "$json" = "1" ]; then
    python3 - "$pane" "$result" "$WAITED" "$FINAL_STREAK" <<'PY'
import sys, json
print(json.dumps({
    "pane": sys.argv[1],
    "result": sys.argv[2],
    "waited_seconds": int(sys.argv[3]),
    "streak": int(sys.argv[4]),
}))
PY
  else
    local window; window="$(python3 -c "print(round($STREAK * $INTERVAL))")"
    case "$rc" in
      0) echo "stable-idle: $pane idle for ~${window}s" ;;
      1) echo "timeout: $pane not stably idle after ${WAITED}s" >&2 ;;
      3) echo "missing: $pane is gone" >&2 ;;
    esac
  fi
  return "$rc"
}

cmd_send() {
  local pane="" text="" file="" have_text=0 force=0 no_enter=0 settle=0.5
  INTERVAL=5; STREAK=3; TIMEOUT=3600
  while [ $# -gt 0 ]; do
    case "$1" in
      --text)     text="$2"; have_text=1; shift 2 ;;
      --file)     file="$2"; shift 2 ;;
      --force)    force=1; shift ;;
      --no-enter) no_enter=1; shift ;;
      --settle)   settle="$2"; shift 2 ;;
      --interval) INTERVAL="$2"; shift 2 ;;
      --streak)   STREAK="$2"; shift 2 ;;
      --timeout)  TIMEOUT="$2"; shift 2 ;;
      -*)         die "send: unknown arg: $1" ;;
      *)          [ -z "$pane" ] || die "send: unexpected arg: $1"; pane="$1"; shift ;;
    esac
  done
  [ -n "$pane" ] || die "send: PANE is required"
  if [ -n "$file" ]; then
    [ "$have_text" = "0" ] || die "send: pass only one of --text / --file"
    [ -f "$file" ] || die "send: file not found: $file"
    text="$(cat "$file")"
  else
    [ "$have_text" = "1" ] || die "send: one of --text / --file is required"
  fi

  # Default: wait for stable idle first so we never type over a working agent.
  # --force is the deliberate escape hatch (interrupt/steer a working agent).
  if [ "$force" = "0" ]; then
    local rc=0; wait_idle_core "$pane" || rc=$?
    case "$rc" in
      1) die "send: $pane not stably idle after ${WAITED}s - not sending (use --force to inject anyway)" ;;
      3) die "send: $pane is gone - not sending" ;;
    esac
  fi

  herdr pane send-text "$pane" "$text"
  if [ "$no_enter" = "1" ]; then
    echo "sent (queued, no Enter): $pane"
  else
    sleep "$settle"
    herdr pane send-keys "$pane" Enter
    echo "sent + submitted: $pane"
  fi
}

cmd_stop() {
  local pane="" wait=0
  INTERVAL=5; STREAK=3; TIMEOUT=3600
  while [ $# -gt 0 ]; do
    case "$1" in
      --wait)     wait=1; shift ;;
      --interval) INTERVAL="$2"; shift 2 ;;
      --streak)   STREAK="$2"; shift 2 ;;
      --timeout)  TIMEOUT="$2"; shift 2 ;;
      -*)         die "stop: unknown arg: $1" ;;
      *)          [ -z "$pane" ] || die "stop: unexpected arg: $1"; pane="$1"; shift ;;
    esac
  done
  [ -n "$pane" ] || die "stop: PANE is required"

  # Deliberate interrupt: send the stop key (Escape) with no idle wait.
  herdr pane send-keys "$pane" Escape
  echo "interrupt sent (Escape): $pane"

  if [ "$wait" = "1" ]; then
    local rc=0; wait_idle_core "$pane" || rc=$?
    case "$rc" in
      0) echo "settled: $pane idle after interrupt (${WAITED}s)" ;;
      1) echo "still not idle after ${WAITED}s" >&2; return 1 ;;
      3) echo "missing: $pane is gone" >&2; return 3 ;;
    esac
  fi
}

[ $# -gt 0 ] || die "usage: herdr-io.sh {wait-idle|send|stop} PANE [options]"
SUB="$1"; shift
case "$SUB" in
  wait-idle) cmd_wait_idle "$@" ;;
  send)      cmd_send "$@" ;;
  stop)      cmd_stop "$@" ;;
  *)         die "unknown subcommand: $SUB (expected wait-idle|send|stop)" ;;
esac
