#!/usr/bin/env bash
# spawn-herdr-task.sh - one-shot: worktree + branch, then a natively-tracked
# child `claude` agent running in its OWN herdr tab. The agent is launched in a
# freshly-created tab (`herdr tab create` + `herdr agent start --tab`) and
# registered as a child of the orchestrator's pane (`herdr agent set-parent`),
# so herdr tracks it in its agent tree (`herdr agent list` / `herdr agent get`).
# Placement and parenting are decoupled on purpose: `agent start --parent` would
# split the parent's pane in the SAME tab instead of opening a new one. Prints a
# JSON summary on stdout so the caller can register the tracked agent.
#
# Usage:
#   spawn-herdr-task.sh --slug SLUG --prompt-file PATH [options]
#
# Options:
#   --slug SLUG          Branch + worktree slug (required). Append the tracker
#                        key for JIRA tasks, e.g. mock-scenario-dropdown-AIE-370.
#   --prompt-file PATH   File whose contents become claude's initial prompt
#                        (required). Passed as claude's positional arg, so
#                        claude starts interactive with the prompt submitted.
#   --title TITLE        Human agent name (herdr uses it as the agent's name; no
#                        prefix). Capped to 29 chars (under 30). Defaults to the
#                        slug (also capped).
#   --tab-number N       Optional ordinal for the tab label. When set, the tab is
#                        labeled "T<N> - <title>" (prefix on the TAB label only;
#                        the agent name stays the raw title). Used by the
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

# Cap the agent name under 30 chars (herdr uses it as the agent name).
if [ "${#TITLE}" -gt 29 ]; then
  echo "spawn-herdr-task: title too long (${#TITLE} chars), truncating to 29" >&2
  TITLE="${TITLE:0:29}"
fi

# Tab label: the raw title, optionally prefixed "T<N> - " when --tab-number is
# given. The prefix is on the TAB label only (what shows in the tab bar); the
# agent name stays the raw TITLE so tracker reports read cleanly.
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

# 3. create a dedicated tab (labeled with the title). A fresh tab always comes
#    with a root shell pane; we launch the agent as a split of it and then close
#    that shell (step 5) so the tab ends up holding only the agent.
TAB_JSON="$(herdr tab create --workspace "$WORKSPACE" --label "$TAB_LABEL" --no-focus)"
read -r NEW_TAB ROOT_SHELL <<EOF
$(printf '%s' "$TAB_JSON" | python3 -c '
import sys, json
r = json.load(sys.stdin)["result"]
print(r["tab"]["tab_id"], r["root_pane"]["pane_id"])
')
EOF
[ -n "$NEW_TAB" ] && [ -n "$ROOT_SHELL" ] || die "failed to parse tab create response"

# 4. launch the agent in that tab. --tab targets the new tab; agent start splits
#    its focused (root) pane, cd's to --cwd, and starts claude interactive with
#    the prompt as claude's positional arg (single argv element over the socket,
#    no shell re-parse - multiline prompts are safe).
AGENT_JSON="$(herdr agent start "$TITLE" --tab "$NEW_TAB" --cwd "$WORKTREE" --no-focus -- claude "$(cat "$PROMPT_FILE")")"
read -r ROOT_PANE TAB_ID WORKSPACE AGENT_NAME <<EOF
$(printf '%s' "$AGENT_JSON" | python3 -c '
import sys, json
a = json.load(sys.stdin)["result"]["agent"]
print(a["pane_id"], a["tab_id"], a["workspace_id"], a["name"])
')
EOF
[ -n "$ROOT_PANE" ] && [ -n "$TAB_ID" ] || die "failed to parse agent start response"

# 5. close the leftover root shell so the tab holds only the agent pane, then
#    register the agent under the orchestrator for native tracking. Parenting is
#    a separate call because `agent start --parent` places (splits), it does not
#    open a new tab.
herdr pane close "$ROOT_SHELL" >/dev/null || die "failed to close root shell pane $ROOT_SHELL"
AGENT_PARENT="$(herdr agent set-parent "$ROOT_PANE" "$PARENT" | python3 -c 'import sys, json; print(json.load(sys.stdin)["result"]["agent"].get("parent",""))')" \
  || die "failed to set agent parent"

# 6. machine-readable summary for the caller (task-tool registration).
#    tab_label = the actual tab label (carries the "T<N> - " prefix when
#    --tab-number was set); root_pane = the agent's pane_id; parent = the
#    orchestrator pane it is tracked under.
python3 - "$SLUG" "$AGENT_NAME" "$WORKTREE" "$SLUG" "$WORKSPACE" "$TAB_ID" "$TAB_LABEL" "$ROOT_PANE" "$PROMPT_FILE" "$AGENT_PARENT" <<'PY'
import sys, json
keys = ["slug","title","worktree","branch","workspace","tab_id","tab_label","root_pane","prompt_file","parent"]
print(json.dumps(dict(zip(keys, sys.argv[1:])), indent=2))
PY
