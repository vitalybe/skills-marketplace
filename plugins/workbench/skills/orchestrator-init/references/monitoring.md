# Monitoring - the tracker, and handling its exits

Monitoring is split so the orchestrator's context stays clean:

- **`scripts/track-children.py`** - a one-shot tracker. It blocks until a
  *settled* change among the orchestrator's child agents, prints that change,
  and exits. It never loops inside the orchestrator.
- **The orchestrator owns the loop.** It runs the tracker as a
  `run_in_background` process (NOT inside a subagent), handles each exit, then
  relaunches exactly one tracker. The pane-read + doc-edit work can be offloaded
  to a bounded, non-blocking subagent so that noise stays out of the
  orchestrator's context.

## The tracker

```bash
${CLAUDE_PLUGIN_ROOT}/skills/orchestrator-init/scripts/track-children.py --parent <ORCH_PANE>
```

It enumerates the children of `--parent` with `herdr agent children` (defaults
to `$HERDR_PANE_ID`) and watches their `agent_status`:

1. **Steady phase** - while nothing differs from the persisted baseline,
   re-check every **20s** (`--poll`).
2. **Debounce phase** - as soon as any child differs, track every differing
   child **in parallel**, re-checking every **30s** (`--debounce`). A child
   settles once its status holds for one debounce interval; a child still
   flapping after **180s** (`--max-debounce`) settles by timeout. A child that
   reverts to its baseline status was a blip and is dropped. The window is long
   on purpose: an agent pausing between steps is back to `working` well inside
   it and never wakes anyone, while a real gate sits unanswered for minutes.
3. On a settled change it folds the new statuses into the baseline, filters the
   report to *actionable* changes, and - if anything survives - writes the
   report, prints it as JSON, and **exits 0**. If nothing survives it keeps
   polling.

A "change" is either a child's `agent_status` changing **or** a child appearing
/ disappearing (task spawned / tab closed).

### What counts as actionable

Every exit costs the orchestrator a turn, so the tracker only exits when there
is something to decide. Two kinds of settle are dropped and logged as
`suppressed` instead:

- **`-> working`** - the child resumed running (typically an auto-cleared
  permission prompt in drivethrough mode). Never a gate.
- **stopped `->` stopped** - `done->idle`, `blocked->done`, `idle->blocked` and
  friends. herdr's stopped labels (`idle` / `done` / `blocked` / `paused`) are
  interchangeable and drift on their own while an agent sits at one unanswered
  prompt. The child did not run in between, so the pane still holds exactly what
  you read last time.

What survives is a child crossing from `working` into a stopped state, plus
`appeared` / `disappeared`.

### State - `/tmp/herdr-monitoring/`

Persisted so each cycle continues where the last left off:

- `baseline.json` - `{pane_id: {"status", "name"}}`, the last settled snapshot.
- `latest.json` - the change report from the most recent settled exit.
- `log.jsonl` - one JSON line per settled exit (history / debug).

Because the baseline persists, a restart compares immediately at startup, so a
change that lands during the exit/restart gap is not missed. Pass `--reset` to
start a fresh baseline.

### Report shape

`latest.json` / stdout is a list of change records:

```json
[
  {"pane": "w13:p30", "name": "admin-access-commits",
   "from": "working", "to": "blocked", "kind": "status", "timed_out": false}
]
```

`kind` is `status` | `appeared` | `disappeared`; `from`/`to` are `null` for
appear/disappear; `timed_out` means the child settled by the `--max-debounce`
cap rather than by stabilising.

## Handling a tracker exit

Run the tracker as an orchestrator-owned `run_in_background` Bash process - never
as a blocking call inside a subagent. A subagent's Bash is capped (~600s); the
blocked tracker is orphaned, the subagent returns a false "still waiting", and
duplicate trackers accumulate and race the state file. Keep exactly one alive;
relaunch exactly one per exit, WITHOUT `--reset` (the baseline persists, so the
exit/relaunch gap misses nothing).

On each exit read `latest.json` and handle every change. You may offload the pane
reads + doc edit to a **bounded, non-blocking** subagent (a `general-purpose`
Agent that runs NO watcher/tracker and no blocking loop) to keep that noise out
of your context; give it the pane ids, the target-doc path, and the rules below.

**Say nothing when nothing changed.** A monitoring exit is machine chatter, not
a user request. If handling it produced no doc edit and no decision the user
needs - a `timed_out` watcher exit, a pane still parked at the same gate you
already reported, a finished task you already surfaced - relaunch the loop and
end the turn with **no user-facing text at all**. Do not narrate "watcher timed
out, relaunched", "both loops healthy", or "still waiting". A session where the
orchestrator speaks on every wake-up reads as if it is firing constantly even
when the loops are behaving; speak only when the status changed or the user has
something to answer.

Rules for classifying and acting on a change:

- **`to` = `idle` or `done` does NOT mean finished.** It means the agent went
  idle - which includes sitting at an approval / permission / requirements gate.
  herdr's label is inconsistent: the same waiting-at-a-gate state surfaces as
  `blocked` on one agent and `idle` or `done` on another. ALWAYS
  `herdr pane read <pane> --source recent` before classifying. A task parked at a
  gate is **waiting for input** - label it that, never "done". A task is finished
  only once the pane says the code phase is complete/committed AND its branch has
  real implementation commits.
- **Never auto-merge, integrate, close, or clean up.** On a genuine finish,
  surface "X is ready to integrate" and wait for the user's **explicit
  confirmation** before merging. Never close herdr tabs.
- **Do not proxy in-pane gates.** The user answers requirements / plan /
  permission gates directly in the tab; summarize them in the doc - do not relay
  them via AskUserQuestion or answer them yourself. Message a tab only for an
  obvious self-serve action (e.g. a design upload the orchestrator can do
  itself), with `SendMessage` - see `/workbench:task-herdr`, "Talking to /
  stopping a tab". The sole exception is a task the user explicitly told you to
  drive - then answer that task's gates per `/workbench:orchestrator-drive`.
- Update the status doc to current state per
  [status-doc-format.md](status-doc-format.md) - current-state voice; never write
  "was X now Y".

`<ORCH_PANE>` is your `$HERDR_PANE_ID`; `<TARGET_PATH>` comes from the
`orchestrator-target` pointer file.

## Common mistakes

- **Do not type prose into a pane.** Ordinary messages to a tab go through
  `SendMessage`, which queues safely and needs no idle guard - the whole class of
  "typed over a working agent" and "fired into an option picker" failures comes
  from typing keystrokes. Keystrokes are for option pickers and Escape only.
- **Answer a numbered-option gate with the bare option number**, atomically, via
  `herdr-io.sh send <pane> --text "<n>" --force`. `SendMessage` does NOT clear a
  picker - it queues as the agent's next prompt while the gate stays open.
- **Do not relaunch a second loop "just in case".** Exactly one tracker and one
  watcher. `pgrep -f "track-children.py|watch-pending.py"` before relaunching if
  you are unsure - duplicates race the shared `baseline.json` and each duplicate
  multiplies the wake-ups.
- **Do not shorten `--debounce` to feel more responsive.** This applies to both
  loops. On the tracker a short window turns every between-steps pause into a
  wake-up; on the pending watcher it turns every pause in the user's *typing*
  into a dispatch of a half-written item. Detecting a real gate or a new item
  ~60s later costs nothing; waking early costs a turn each time and can spawn a
  task from an unfinished line.

## The pending-tasks watcher (task-creator)

An optional second loop that dispatches new work the user drops under a
`## Pending tasks` heading in the status doc. It is independent of the child
tracker: the tracker watches *running* tabs, this watches the *doc* for new
items to spawn.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/orchestrator-init/scripts/watch-pending.py \
  --file "<TARGET>" --state-dir <scratchpad>/pending-watch --max-wait 3300
```

It parses the `## Pending tasks` section: each top-level `- [ ]` line with a
non-empty title (plus its indented sub-bullets) is an item. Checked (`- [x]`)
and empty-title lines are ignored. Behaviour:

1. **Steady phase** - re-check every **15s** (`--poll`) until the set of item
   titles differs from the persisted baseline.
2. **Quiet-window phase** - once something differs, re-look every 3s and require
   the doc to hold still for **20s** (`--debounce`) before settling, capped at
   **180s** (`--max`). "Hold still" means both the full text of every item's
   block (title *and* its indented sub-bullets) and the file's **mtime** are
   unchanged - so a keystroke anywhere in the doc restarts the window and the
   user finishes writing before the orchestrator wakes.
3. On a settled change with **newly added** items, print
   `{"added":[{title,block}...], "all_current":[...], "still_editing":<bool>}`
   and **exit 0**. A removal-only change (items moved out to `## Tasks`) is
   folded into the baseline silently and polling continues.
   `still_editing:true` means the `--max` cap settled it while the doc was
   *still* changing: an item may be half-written, so re-read the section before
   dispatching rather than trusting the reported block.
4. With `--max-wait` set, exit 0 with `{"added":[], "timed_out":true}` after that
   many idle seconds, so the caller can relaunch cleanly instead of being killed
   by a shell timeout.

Modes: `--seed` (baseline := current items, then exit - run this once at setup so
pre-existing items do not auto-fire), `--once` (single check vs baseline),
`--reset` (clear baseline first). State is `<state-dir>/baseline.json` (a list of
item titles), persisted so a relaunch misses nothing across the exit/relaunch gap.

### Run it as an orchestrator-owned background process

Do NOT run this blocking watcher inside a subagent: the subagent's Bash call is
capped (~600s); when the watcher blocks past that it is orphaned to the
background, the subagent returns a false "still waiting", and duplicate loops
pile up racing `baseline.json`. Instead the orchestrator owns the loop as a
`run_in_background` Bash process (no cap; the harness re-invokes the orchestrator
when it exits). Keep EXACTLY ONE watcher alive; relaunch exactly one per exit.

On each exit the orchestrator, INLINE:

- If `added` is non-empty, spawn a bounded **dispatch subagent** (a `sonnet`
  `general-purpose` Agent that does non-blocking work and runs NO watcher). For
  each added item it: passes the item's intent + the integration rule (e.g.
  `no-pr` on a side branch) + the next tab number to `/workbench:task-herdr`,
  **letting task-herdr author the exact prompt** and spawn the tab. It does NOT
  pick a route - task-herdr tells the agent to run devflow and devflow triages the
  depth (fast-path vs full flow) itself. It moves the item's block from
  `## Pending tasks` to `## Tasks` and records the spawn JSON.
- Then **relaunches** exactly one watcher in the background (no `--reset`).

The dispatch subagent never writes prompt prose itself - task-herdr is the single
owner of the spawned tab's prompt text. Tab numbers come from the
`<scratchpad>/tab-counter` pointer (see orchestrator-init §5); read-and-increment
it per spawn so tabs are labeled `T<n> - <Name>` by spawn order.

### The doc is a file the user has open - edit it narrowly

The status doc is live in the user's editor, and a dispatch lands right after
they wrote the item that triggered it - which is often while they are typing the
*next* one. So:

- **Delete only the exact block you dispatched.** One narrow `Edit` whose
  `old_string` is that item's own lines. Never rewrite `## Pending tasks` (or any
  section) wholesale, and never reconstruct neighbouring lines from your read -
  their content may be one keystroke old.
- **On "File has been modified since read", re-`Read` and retry the narrow
  delete once.** If it conflicts again, the user is actively typing: leave the
  item where it is, dispatch stands, and pick the doc edit up on a later wake.
  Never widen the edit to force it through.
- **A partial line is not an item.** If a re-read shows a truncated title
  (`- [ ] Is it st`), you caught a half-typed line. Do not dispatch it and do not
  write it anywhere - drop it and let the watcher settle it properly.
