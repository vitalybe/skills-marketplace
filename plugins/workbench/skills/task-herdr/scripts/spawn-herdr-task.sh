#!/usr/bin/env bash
# spawn-herdr-task.sh - one-shot: worktree + branch, then a natively-tracked
# child `claude` agent running in its OWN herdr tab. A fresh tab is created in
# the worktree (`herdr tab create --cwd`), claude is started in that tab's root
# shell pane (`herdr agent start --kind claude --pane`), and the agent is
# registered as a child of the orchestrator's pane (`herdr agent set-parent`),
# so herdr tracks it in its agent tree (`herdr agent list` / `herdr agent get`).
# Placement and parenting are decoupled on purpose: the tab decides where the
# agent lives, set-parent only records the tracking relationship. Prints a JSON
# summary on stdout so the caller can register the tracked agent.
#
# Usage:
#   spawn-herdr-task.sh --slug SLUG --prompt-file PATH [options]
#
# Options:
#   --slug SLUG          Branch + worktree slug (required). Append the tracker
#                        key for JIRA tasks, e.g. mock-scenario-dropdown-AIE-370.
#   --prompt-file PATH   File whose contents become claude's initial prompt
#                        (required). Pasted into the ready claude session and
#                        submitted, so claude starts on the task right away.
#   --title TITLE        Human title for the tab. A slugified form of it
#                        (lowercase, kebab-case) is used BOTH as herdr's agent
#                        name and as `claude --name`, so the herdr agent name
#                        doubles as the agent's SendMessage address. No prefix.
#                        Capped to 29 chars. Defaults to the slug.
#   --tab-number N       Optional ordinal for the tab label. When set, the tab is
#                        labeled "T<N> - <title>" (prefix on the TAB label only;
#                        the agent name stays the title's slug). Used by the
#                        orchestrator to number tabs by chronological spawn order.
#   --parent TARGET      Parent pane/agent to register under. Default:
#                        $HERDR_PANE_ID (the orchestrator's pane). Required -
#                        the point is to register a tracked child agent.
#   --base REF           Branch off this ref. Default: origin/main.
#   --workspace WS       herdr workspace id. Optional - --parent implies the
#                        workspace; only pass to override where the agent lands.
#   --repo-root DIR      Repo root. Default: `git rev-parse --show-toplevel`.
#
# Requires: git, herdr (HERDR_ENV=1), python3, claude on PATH.
set -euo pipefail

die() { echo "spawn-herdr-task: $*" >&2; exit 1; }

SLUG=""; PROMPT_FILE=""; TITLE=""; PARENT="${HERDR_PANE_ID:-}"; BASE="origin/main"; WORKSPACE=""; REPO_ROOT=""; TAB_NUMBER=""
while [ $# -gt 0 ]; do
  case "$1" in
    --slug)        SLUG="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --title)       TITLE="$2"; shift 2 ;;
    --tab-number)  TAB_NUMBER="$2"; shift 2 ;;
    --parent)      PARENT="$2"; shift 2 ;;
    --base)        BASE="$2"; shift 2 ;;
    --workspace)   WORKSPACE="$2"; shift 2 ;;
    --repo-root)   REPO_ROOT="$2"; shift 2 ;;
    *) die "unknown arg: $1" ;;
  esac
done

[ -n "$SLUG" ]        || die "--slug is required"
[ -n "$PROMPT_FILE" ] || die "--prompt-file is required"
[ -f "$PROMPT_FILE" ] || die "prompt file not found: $PROMPT_FILE"
[ "${HERDR_ENV:-}" = "1" ] || die "not inside herdr (HERDR_ENV != 1)"
command -v herdr  >/dev/null 2>&1 || die "herdr not on PATH"
command -v python3 >/dev/null 2>&1 || die "python3 not on PATH"
[ -n "$PARENT" ] || die "no parent pane - set \$HERDR_PANE_ID or pass --parent <pane> (required to register a tracked child agent)"
[ -n "$TITLE" ] || TITLE="$SLUG"

# Cap the title under 30 chars (it also seeds the agent name below).
if [ "${#TITLE}" -gt 29 ]; then
  echo "spawn-herdr-task: title too long (${#TITLE} chars), truncating to 29" >&2
  TITLE="${TITLE:0:29}"
fi

# herdr agent names are identifiers, not labels: a lowercase leading letter,
# then [a-z0-9_-] only, at most 32 characters. `agent start` rejects anything
# else, which leaves the tab holding a bare shell and the task unrun. So the
# title is slugified once here and used for BOTH the herdr agent name and
# `claude --name`, keeping the two identical so the name in `herdr agent list`
# is still the agent's SendMessage address. The tab label keeps the raw title.
AGENT_ID="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
case "$AGENT_ID" in
  [a-z]*) ;;
  *) AGENT_ID="task${AGENT_ID:+-$AGENT_ID}" ;;
esac
AGENT_ID="$(printf '%s' "$AGENT_ID" | cut -c1-32 | sed -E 's/-+$//')"

# Tab label: the raw title, optionally prefixed "T<N> - " when --tab-number is
# given. The prefix is on the TAB label only (what shows in the tab bar); the
# agent name stays $AGENT_ID so tracker reports read cleanly.
TAB_LABEL="$TITLE"
if [ -n "$TAB_NUMBER" ]; then
  case "$TAB_NUMBER" in
    ''|*[!0-9]*) die "--tab-number must be a positive integer, got: $TAB_NUMBER" ;;
  esac
  TAB_LABEL="T${TAB_NUMBER} - ${TITLE}"
fi

if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(git rev-parse --show-toplevel)" || die "not in a git repo"
fi
WORKTREE="$REPO_ROOT/.worktrees/$SLUG"
[ -e "$WORKTREE" ] && die "worktree already exists: $WORKTREE"

# 1. worktree + branch
git -C "$REPO_ROOT" fetch origin --quiet || true
git -C "$REPO_ROOT" worktree add "$WORKTREE" -b "$SLUG" "$BASE" >&2

# 2. resolve the workspace to open the tab in. --workspace overrides; otherwise
#    use the parent (orchestrator) pane's workspace.
if [ -z "$WORKSPACE" ]; then
  WORKSPACE="$(herdr pane get "$PARENT" | python3 -c 'import sys, json; print(json.load(sys.stdin)["result"]["pane"]["workspace_id"])')" \
    || die "could not resolve workspace from parent pane $PARENT"
fi
[ -n "$WORKSPACE" ] || die "empty workspace"

# 3. create a dedicated tab (labeled with the title), rooted in the worktree. A
#    fresh tab comes with a root shell pane already sitting at its prompt in
#    --cwd, which is exactly what `agent start` needs, so that pane becomes the
#    agent's own pane and the tab ends up holding only the agent.
TAB_JSON="$(herdr tab create --workspace "$WORKSPACE" --cwd "$WORKTREE" --label "$TAB_LABEL" --no-focus)"
read -r NEW_TAB ROOT_SHELL <<EOF
$(printf '%s' "$TAB_JSON" | python3 -c '
import sys, json
r = json.load(sys.stdin)["result"]
print(r["tab"]["tab_id"], r["root_pane"]["pane_id"])
')
EOF
[ -n "$NEW_TAB" ] && [ -n "$ROOT_SHELL" ] || die "failed to parse tab create response"

# 4. wait for that shell to reach its prompt before typing at it. While it is
#    still running its startup files a subprocess owns the pane's foreground job,
#    and agent start rejects such a pane as busy. Resolved against a concrete
#    signal (the pane's foreground process is its own shell), not a sleep.
for _ in $(seq 1 40); do
  INFO="$(herdr pane process-info --pane "$ROOT_SHELL" 2>/dev/null)" || { sleep 0.25; continue; }
  read -r FG SHELL_PID <<EOF
$(printf '%s' "$INFO" | python3 -c '
import sys, json
p = json.load(sys.stdin)["result"]["process_info"]
print(p.get("foreground_process_group_id") or "", p.get("shell_pid") or "")
')
EOF
  [ -n "$FG" ] && [ "$FG" = "$SHELL_PID" ] && break
  sleep 0.25
done

# 5. start claude in that root pane. agent start types the claude command line
#    into the pane's shell prompt and blocks until claude is detected and ready
#    for input. The prompt is deliberately NOT a claude argument: a large
#    multiline argument typed into an interactive shell is fragile (line
#    continuation, bracketed paste, paste chunking), so step 6 delivers it.
#    `claude --name "$AGENT_ID"` sets the session's display name to the SAME
#    string herdr uses as the agent name, so the name in `herdr agent list` is
#    also the SendMessage address for that agent.
AGENT_JSON="$(herdr agent start "$AGENT_ID" --kind claude --pane "$ROOT_SHELL" --timeout 120000 -- --name "$AGENT_ID")"
read -r ROOT_PANE TAB_ID WORKSPACE AGENT_NAME <<EOF
$(printf '%s' "$AGENT_JSON" | python3 -c '
import sys, json
a = json.load(sys.stdin)["result"]["agent"]
print(a["pane_id"], a["tab_id"], a["workspace_id"], a["name"])
')
EOF
[ -n "$ROOT_PANE" ] && [ -n "$TAB_ID" ] || die "failed to parse agent start response"

# 6. deliver the prompt. agent start already returned only once claude was ready
#    for input, so what remains is the paste race: an Enter fired in the same
#    breath as the text gets coalesced into the bracketed paste and swallowed. So
#    send-text the prompt, wait until a stable prefix of it shows up in the input
#    (deterministic, no arbitrary sleep), then press Enter as a separate
#    keystroke so it cannot merge with the paste.
PROMPT_TEXT="$(cat "$PROMPT_FILE")"
PROMPT_HEAD="${PROMPT_TEXT%%$'\n'*}"
herdr pane send-text "$ROOT_PANE" "$PROMPT_TEXT" >/dev/null || die "failed to send prompt to pane $ROOT_PANE"
herdr pane wait-output "$ROOT_PANE" --match "${PROMPT_HEAD:0:40}" --timeout 10000 >/dev/null 2>&1 || sleep 1
herdr pane send-keys "$ROOT_PANE" Enter >/dev/null || die "failed to submit prompt in pane $ROOT_PANE"

# 7. register the agent under the orchestrator for native tracking. Placement and
#    parenting stay separate calls: the tab created in step 3 decides where the
#    agent lives, and set-parent only records the tracking relationship.
AGENT_PARENT="$(herdr agent set-parent "$ROOT_PANE" "$PARENT" | python3 -c 'import sys, json; print(json.load(sys.stdin)["result"]["agent"].get("parent",""))')" \
  || die "failed to set agent parent"

# 8. machine-readable summary for the caller (task-tool registration).
#    tab_label = the actual tab label (carries the "T<N> - " prefix when
#    --tab-number was set); root_pane = the agent's pane_id; parent = the
#    orchestrator pane it is tracked under.
python3 - "$SLUG" "$AGENT_NAME" "$WORKTREE" "$SLUG" "$WORKSPACE" "$TAB_ID" "$TAB_LABEL" "$ROOT_PANE" "$PROMPT_FILE" "$AGENT_PARENT" <<'PY'
import sys, json
keys = ["slug","title","worktree","branch","workspace","tab_id","tab_label","root_pane","prompt_file","parent"]
print(json.dumps(dict(zip(keys, sys.argv[1:])), indent=2))
PY
