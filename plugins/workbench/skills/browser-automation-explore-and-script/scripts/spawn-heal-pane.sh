#!/usr/bin/env bash
# spawn-heal-pane.sh - called BY a failing automation script to put a `claude`
# healer in a herdr pane directly BELOW the pane the script just failed in. The
# healer reads the run log, fixes the script, and retries it by driving the pane
# above (the operator's own pane, still holding the failed run), so the retry is
# visible and runs in the same shell/session/profile as the original.
#
# Usage (from the failing script's error path):
#   spawn-heal-pane.sh --script PATH --cmd 'STR' --log PATH \
#                      [--debug-dir PATH] [--error 'STR'] [--pane ID] [--name NAME]
#
#   --script PATH     The script to fix. Required.
#   --cmd STR         Exact command that failed, to re-run verbatim. Required.
#   --log PATH        Run log the script wrote. Required - it is the healer's
#                     primary evidence, so a script with no log has nothing to
#                     heal from.
#   --debug-dir PATH  Screenshots / DOM snapshots directory, if the script keeps one.
#   --error STR       The failure message, quoted into the prompt.
#   --pane ID         Pane to split and drive. Default: $HERDR_PANE_ID.
#   --name NAME       Healer agent name. Default: heal-<script basename>.
#
# NEVER fails its caller: every guard and every herdr error exits 0 after a
# warning on stderr. A broken healer must not mask the original failure, and the
# caller has already decided its own exit code.
#
# Requires: herdr (HERDR_ENV=1), python3, claude on PATH.
set -uo pipefail

warn() { echo "spawn-heal-pane: $*" >&2; }
skip() { warn "$* - skipping self-heal"; exit 0; }

SCRIPT=""; CMD=""; LOG=""; DEBUG_DIR=""; ERROR=""; PANE="${HERDR_PANE_ID:-}"; NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --script)    SCRIPT="$2"; shift 2 ;;
    --cmd)       CMD="$2"; shift 2 ;;
    --log)       LOG="$2"; shift 2 ;;
    --debug-dir) DEBUG_DIR="$2"; shift 2 ;;
    --error)     ERROR="$2"; shift 2 ;;
    --pane)      PANE="$2"; shift 2 ;;
    --name)      NAME="$2"; shift 2 ;;
    *) skip "unknown arg: $1" ;;
  esac
done

# Recursion guard, both halves. The healer re-runs the script with SELFHEAL=0
# (its prompt says so below), and this refuses to spawn when it sees that - so a
# retry that fails again reports to the existing healer instead of stacking a new
# pane under every attempt.
[ "${SELFHEAL:-1}" = "0" ] && exit 0
[ -n "$SCRIPT" ] && [ -n "$CMD" ] && [ -n "$LOG" ] || skip "need --script, --cmd and --log"
[ "${HERDR_ENV:-}" = "1" ] || skip "not inside herdr (HERDR_ENV != 1)"
command -v herdr   >/dev/null 2>&1 || skip "herdr not on PATH"
command -v python3 >/dev/null 2>&1 || skip "python3 not on PATH"
command -v claude  >/dev/null 2>&1 || skip "claude not on PATH"
[ -n "$PANE" ] || skip "no pane to split (set \$HERDR_PANE_ID or pass --pane)"

# Agent names are identifiers: lowercase leading letter, then [a-z0-9_-], <=32
# chars. `agent start` rejects anything else, which would leave a bare shell
# sitting in a split pane.
[ -n "$NAME" ] || NAME="heal-$(basename "$SCRIPT" | sed -E 's/\.[^.]+$//')"
NAME="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
case "$NAME" in [a-z]*) ;; *) NAME="heal${NAME:+-$NAME}" ;; esac
NAME="$(printf '%s' "$NAME" | cut -c1-32 | sed -E 's/-+$//')"

TMP="${TMPDIR:-/tmp}"; TMP="${TMP%/}"   # macOS $TMPDIR carries a trailing slash
RETRY_LOG="$TMP/${NAME}-retry.log"

# Is the pane we would drive a shell, or a live agent session? When an AGENT ran
# this script through its own tool call, $HERDR_PANE_ID is that agent's pane, and
# typing a command into it interrupts the agent's turn instead of running
# anything. So the pane above is only the retry target when it holds a plain
# shell; otherwise the healer retries in its own pane and leaves that one alone.
PANE_AGENT="$(herdr pane get "$PANE" 2>/dev/null | python3 -c '
import sys, json
try: print(json.load(sys.stdin)["result"]["pane"].get("agent") or "")
except Exception: pass
')"

# 1. Split the failing pane downward. The healer goes BELOW so the pane above
#    keeps the failed output on screen for the operator to read.
SPLIT="$(herdr pane split --pane "$PANE" --direction down --ratio 0.4 --cwd "$(dirname "$SCRIPT")" 2>&1)" \
  || skip "pane split failed: $SPLIT"
HEAL_PANE="$(printf '%s' "$SPLIT" | python3 -c '
import sys, json
try: print(json.load(sys.stdin)["result"]["pane"]["pane_id"])
except Exception: pass
')"
[ -n "$HEAL_PANE" ] || skip "could not parse new pane id from: $SPLIT"

# 2. Wait for that shell to reach its prompt. While it still runs its startup
#    files a subprocess owns the foreground job and `agent start` rejects the
#    pane as busy. Resolved against a concrete signal - the pane's foreground
#    process group is its own shell - not a sleep.
for _ in $(seq 1 40); do
  INFO="$(herdr pane process-info --pane "$HEAL_PANE" 2>/dev/null)" || { sleep 0.25; continue; }
  READY="$(printf '%s' "$INFO" | python3 -c '
import sys, json
try:
    p = json.load(sys.stdin)["result"]["process_info"]
    print("yes" if p.get("foreground_process_group_id") and p["foreground_process_group_id"] == p.get("shell_pid") else "")
except Exception: pass
')"
  [ -n "$READY" ] && break
  sleep 0.25
done

# 3. Build the healer's brief. It carries the retry recipe verbatim because each
#    line of it works around a real herdr/pane behaviour the healer would
#    otherwise rediscover the hard way (see the comments in the prompt).
PROMPT_FILE="$(mktemp "$TMP/${NAME}-prompt.XXXXXX")"
{
  cat <<PROMPT
A browser-automation script just failed. Fix it, then prove the fix by re-running it.

  script:    $SCRIPT
  command:   $CMD
  run log:   $LOG
PROMPT
  [ -n "$DEBUG_DIR" ] && echo "  debug dir: $DEBUG_DIR (screenshots + DOM snapshots per step)"
  [ -n "$ERROR" ] && printf '  error:     %s\n' "$ERROR"
  cat <<PROMPT

Work from the log and debug artifacts FIRST - they hold the whole failed run, so
you should not need to re-drive the site to find out what happened.

Then fix the root cause in the script. Two things are never the fix:
  - Working around missing or expired auth in code. If the log says the session
    is signed out or lacks a role (a LOGIN:-class failure), STOP and tell the
    operator what to sign into - do not script around it.
  - Loosening a verification (row counts, scope assertions, reconciliations) to
    make a run pass. An empty-but-valid result is the failure those checks exist
    to catch.

PROMPT
  if [ -z "$PANE_AGENT" ]; then
  cat <<PROMPT
## Retry by driving the pane above you

Your pane is a split under the operator's pane $PANE, which still shows the
failed run. Re-run there, not here: that pane has the shell, environment and
browser session the script actually runs in, and the operator can watch it.

    # 1. Clear any leftover text on that pane's prompt line. Without this your
    #    command is APPENDED to whatever is sitting there and runs as garbage.
    herdr pane send-keys $PANE C-c

    # 2. Re-run, wrapped in bash -c. The pane's shell is the operator's login
    #    shell (fish, zsh, ...), so do NOT rely on bash syntax (\$?, \$((...)),
    #    arrays) at the prompt itself. tee keeps the output visible to the
    #    operator while giving you a file to read. SELFHEAL=0 stops the script
    #    from spawning another healer under you if it fails again.
    herdr pane run $PANE "bash -c 'SELFHEAL=0 $CMD 2>&1 | tee $RETRY_LOG; echo RETRY_RC=\\\${PIPESTATUS[0]} >> $RETRY_LOG'"

    # 3. Wait for the run to finish by polling that file for the RETRY_RC line.
    #    Do NOT use \`herdr pane wait-output\` to match text that also appears in
    #    the command you just typed - the pane echoes your command, so it matches
    #    instantly and you will read a result that has not happened yet.
    until rg -q '^RETRY_RC=' $RETRY_LOG 2>/dev/null; do sleep 5; done
    tail -40 $RETRY_LOG

    # If you do need to look at the pane itself, read it with --source visible.
    herdr pane read $PANE --source visible --lines 60
PROMPT
  else
  cat <<PROMPT
## Retry in your own pane

The pane above you ($PANE) is a live \`$PANE_AGENT\` session, not a shell - an agent
ran this script through a tool call. Do NOT send keys or commands to it: that
interrupts its turn instead of running anything. Leave that pane alone.

Retry in your own pane instead, with SELFHEAL=0 so a second failure reports back to
you rather than stacking another healer pane underneath you:

    SELFHEAL=0 $CMD

Say in your summary that the retry ran in your pane, so any state that existed only
in the caller's environment was not reproduced.
PROMPT
  fi
  cat <<PROMPT

A clean exit plus the script's own success signal - the JSON line with the row count
and output path - means fixed. Anything else: read the fresh log, fix, retry. After
three failed retries stop and report what you learned instead of continuing to guess.

When you are done, print a short summary: root cause, what you changed, and the
final row count / output path. Leave this pane open.
PROMPT
} > "$PROMPT_FILE"

# 4. Start claude in the split pane. The prompt is deliberately not passed as an
#    argument - a large multiline argument typed at an interactive shell prompt
#    is fragile (line continuation, bracketed paste, chunking) - so step 5
#    delivers it.
START="$(herdr agent start "$NAME" --kind claude --pane "$HEAL_PANE" --timeout 120000 -- --name "$NAME" 2>&1)" || {
  warn "agent start failed: $START"
  warn "healer pane $HEAL_PANE is open at a shell; prompt kept at $PROMPT_FILE"
  exit 0
}

# 5. Deliver the prompt. `agent start` only returns once claude is ready for
#    input, so what is left is the paste race: an Enter fired in the same breath
#    as the text gets coalesced into the bracketed paste and swallowed. Send the
#    text, wait until a stable prefix of it appears, then press Enter separately.
PROMPT_TEXT="$(cat "$PROMPT_FILE")"
if herdr pane send-text "$HEAL_PANE" "$PROMPT_TEXT" >/dev/null 2>&1; then
  herdr pane wait-output "$HEAL_PANE" --match "A browser-automation script just failed" --timeout 10000 >/dev/null 2>&1 || sleep 1
  herdr pane send-keys "$HEAL_PANE" Enter >/dev/null 2>&1 || warn "could not submit prompt in $HEAL_PANE"
  rm -f "$PROMPT_FILE"
else
  warn "could not send prompt to $HEAL_PANE; it is kept at $PROMPT_FILE"
fi

warn "self-heal agent '$NAME' started in pane $HEAL_PANE (below $PANE)"
exit 0
