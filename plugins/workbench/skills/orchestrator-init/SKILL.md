---
name: orchestrator-init
description: Initialize an orchestration session's live status document (the "target") and keep it current. Use at the START of any orchestration/multi-task session - whenever the user says things like "start an orchestration session", "orchestrate these tasks", "here's the status doc / target", "track everything in this doc", or "we'll open several tasks and monitor them". Also use whenever the user hands over a markdown file to serve as the session's status target. If a session is about to run several tasks in parallel and no status target is established yet, invoke this skill.
---

# orchestrator-init - establish the session status doc

An orchestration session runs several tasks in parallel (each in its own tracked
herdr tab, spawned per §4). This skill sets up the single markdown
**status document** ("the target") for the session and defines the contract
for keeping it current. It does not open or monitor tasks.

## 1. Receive the target

The user provides an absolute path to a markdown file that serves as the live
orchestration status. If they don't have one yet, offer to create it at a path
they choose, structured per
[references/status-doc-format.md](references/status-doc-format.md).

## 2. Remember it durably (survives compaction)

Immediately write the target's **absolute path** to a fixed pointer file in
your scratchpad directory (the "Scratchpad Directory" in the system prompt):

```
<scratchpad>/orchestrator-target
```

One line: the path. Nothing else. The scratchpad path is always present in the
environment, so this pointer is recoverable after a context compaction.

**Rule:** the pointer file is the source of truth for the target path. If you
are ever unsure which doc is the target (e.g. after a compaction), read the
pointer file to recover it, then keep using that doc for the rest of the
session.

## 3. Keep it live - an orchestrator-owned tracker

Track the running tasks by owning a background tracker, and keep the noisy work
(polling, pane reads, doc edits) out of your main context.

Run the child tracker as a `run_in_background` Bash process **you own** - never a
blocking loop inside a subagent. A subagent's Bash call is capped (~600s); a
tracker that blocks past it is orphaned, the subagent returns a false "still
waiting", and duplicate trackers pile up racing the state file. As an owned
background process the tracker has no cap and the harness re-invokes you when it
exits:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/orchestrator-init/scripts/track-children.py --parent <YOUR_PANE>
```

`<YOUR_PANE>` is your `$HERDR_PANE_ID`. It blocks until a child's status settles
(or a child appears/disappears), persists state in `/tmp/herdr-monitoring/`,
prints the change JSON (also `/tmp/herdr-monitoring/latest.json`), and exits.
Behaviour and report shape: [references/monitoring.md](references/monitoring.md).
Keep exactly one tracker alive; relaunch exactly one per exit (no `--reset` - the
baseline persists across the gap).

The tracker deliberately stays quiet: it only exits for a child crossing from
`working` into a stopped state, or appearing/disappearing. Resumes into
`working`, and drift between herdr's interchangeable stopped labels
(`done`→`idle`, `blocked`→`done`, …), are suppressed - the child did not run, so
the pane holds nothing new. Leave the defaults alone; shortening `--debounce`
turns every between-steps pause into a wake-up.

On each exit, handle the change - you may offload the pane-read + doc-edit to a
**bounded, non-blocking** subagent to keep that noise out of your context - under
these rules:

- **`idle`/`done` from the tracker means the agent went idle, NOT that it
  finished.** herdr's label is unreliable and inconsistent: the same
  waiting-at-a-gate state can surface as `blocked`, `idle`, or `done` across
  agents. **Always read the pane** (`herdr pane read <pane> --source recent`)
  before classifying. A task parked at a requirements/plan/permission gate is
  **waiting for input** - label it that, never "done". Treat a task as finished
  only once the pane says the code phase is complete/committed AND its branch has
  real implementation commits.
- **Never auto-merge, integrate, close, or clean up.** When a task genuinely
  finishes, surface "X is ready to integrate" and wait for the user's **explicit
  confirmation** before merging. Never close herdr tabs.
- **Do not proxy in-pane gates.** The user answers requirements/plan/permission
  gates directly in the tab; you summarize them in the doc - you do not relay
  them via AskUserQuestion or answer them yourself. Message a tab only for an
  obvious self-serve action (e.g. a design upload you can do yourself), with
  `SendMessage`, addressed as `<name-slug> [<ref>]` (ref from `ListAgents`). The
  one exception is when the user explicitly asks you to drive a specific task to
  completion - then answer that task's gates per `/workbench:orchestrator-drive`.
- Update the target doc to current state per
  [references/status-doc-format.md](references/status-doc-format.md) -
  current-state voice, no "was X now Y".
- **Say nothing when nothing changed.** If handling the exit produced no doc edit
  and nothing the user must answer, relaunch and end the turn with **no
  user-facing text** - no "watcher timed out, relaunched", no "both loops
  healthy". Narrating every wake-up is what makes a well-behaved orchestrator
  feel like it is firing constantly.

Then relaunch one tracker and continue.

## 4. Dispatch new pending tasks (optional)

If the user wants new items they drop under a `## Pending tasks` heading to be
picked up and spawned automatically, run the **pending-tasks watcher** alongside
the monitor. The watcher is `scripts/watch-pending.py`; it blocks until newly
added pending items settle, then prints them as JSON.

Run it as an **orchestrator-owned background process** - NOT inside a subagent. A
blocking watcher inside a subagent gets orphaned when the subagent's Bash call
hits its ~600s cap, returns a false "still waiting", and leaves duplicate loops
racing the shared state file. As a `run_in_background` Bash process it has no cap
and the harness re-invokes you when it exits:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/orchestrator-init/scripts/watch-pending.py \
  --file "<TARGET>" --state-dir <scratchpad>/pending-watch --max-wait 3300
```

**Seed the baseline first** so items already present at session start do not
auto-fire (`--seed`); only items added/edited afterward trigger a dispatch.

The watcher waits for the doc to go **quiet** - 20s with neither the items' text
nor the file's mtime changing - so it does not fire mid-sentence. Leave that
window alone; shortening it dispatches half-written items. Only top-level `- [ ]`
lines are items: a plain `- ` bullet under `## Pending tasks` is invisible to the
watcher, so if the user writes one, tell them rather than silently ignoring it
(format: [references/status-doc-format.md](references/status-doc-format.md)).

On each exit:

- If `added` is non-empty, **dispatch each item** as a tab (below), using the
  next **tab number** (see "Tab numbering"). Do NOT pick the route - devflow
  triages the depth (fast-path vs full flow) itself. Move the item's block from `## Pending tasks`
  into `## Tasks` with a **narrow** edit of just that block - the user has the doc
  open and is usually typing the next item, so never rewrite the section and
  never reconstruct their neighbouring lines (see monitoring.md, "The doc is a
  file the user has open"). Dispatch is bounded, non-blocking work (a `sonnet`
  subagent is fine) that must NOT itself run any watcher.
- If `added` is empty (a `timed_out` exit), relaunch and **say nothing** - that
  is the watcher's idle heartbeat, not news.
- Then **relaunch exactly one** watcher in the background (no `--reset` - the
  baseline persists across the exit/relaunch gap so nothing is missed).

Spawn one tracked tab per task (in your own workspace, so the tracker sees it):

```bash
WS=$(herdr pane current | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["workspace_id"])')
PANE=$(herdr tab create --workspace "$WS" --cwd <repo> --label "T<n> - <Name>" --no-focus \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])')
herdr agent start <name-slug> --kind claude --pane "$PANE" --timeout 120000 -- --name <name-slug>
herdr agent prompt <name-slug> "/aie-devflow:start-flow-worktree <intent>. Integration: <rule>."
```

The prompt states only intent + integration rule; devflow triages the route. If `agent start`
rejects the pane as busy, the new shell is still running its startup files - retry
after a second. `<name-slug>` is `[a-z0-9_-]`, max 32 chars.

Keep exactly one watcher alive; relaunch one per exit. Full contract:
[references/monitoring.md](references/monitoring.md).

## 5. Tab numbering

Number every task tab `T<n> - <Name>` by **chronological spawn order** so the
tab bar reads as a stable, ordered list. Keep the next number in a fixed pointer
file that survives compaction:

```
<scratchpad>/tab-counter
```

One line: the next integer (start at `1`). On **each** spawn - whether an
auto-dispatch from the pending-watcher or a task the user asks you to open -
read the counter, use it in the spawned tab's label, then increment and rewrite
the file. The counter only ever grows: it
counts merged/closed tasks too, so numbers are never reused and the sequence
stays stable as tasks come and go. The `T<n> -` prefix lives only on the tab
label; the herdr agent name stays the plain slug.

## Pointers

- Doc structure and line format: [references/status-doc-format.md](references/status-doc-format.md).
- The tracker contract and the pending-tasks watcher: [references/monitoring.md](references/monitoring.md).
- Answering an option picker or interrupting a tab: `orchestrator-drive/scripts/herdr-io.sh send <pane> --text "<n>" --force` / `herdr-io.sh stop <pane>`.
- Driving a task's in-pane gates to completion on the user's explicit request: `/workbench:orchestrator-drive`.
