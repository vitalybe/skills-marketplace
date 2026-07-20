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
   child **in parallel**, re-checking every **5s** (`--debounce`). A child
   settles once its status holds for one debounce interval; a child still
   flapping after **60s** (`--max-debounce`) settles by timeout. A child that
   reverts to its baseline status was a blip and is dropped - this is what
   filters herdr's sub-second idle blips, so no separate stable-idle wait is
   needed.
3. On a settled change it writes the report, folds the new statuses into the
   baseline, prints the report as JSON, and **exits 0**.

A "change" is either a child's `agent_status` changing **or** a child appearing
/ disappearing (task spawned / tab closed).

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
appear/disappear; `timed_out` means the child settled by the 60s cap rather than
by stabilising.

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
  them via AskUserQuestion or answer them yourself. Send input to a tab only for
  an obvious self-serve action (e.g. a design upload the orchestrator can do
  itself), via `/workbench:task-herdr`'s `scripts/herdr-io.sh` (`send` / `stop`).
- Update the status doc to current state per
  [status-doc-format.md](status-doc-format.md) - current-state voice; never write
  "was X now Y".

`<ORCH_PANE>` is your `$HERDR_PANE_ID`; `<TARGET_PATH>` comes from the
`orchestrator-target` pointer file.

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
2. **Debounce phase** - once something differs, settle changes every **5s**
   (`--debounce`), capped at **60s** (`--max`), so a user still typing does not
   fire a half-written item.
3. On a settled change with **newly added** items, print
   `{"added":[{title,block}...], "all_current":[...]}` and **exit 0**. A
   removal-only change (items moved out to `## Tasks`) is folded into the
   baseline silently and polling continues.
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
  each added item it: decides the route (`simple` for a trivial/visual tweak,
  `devflow` for a real feature - default `devflow` when unsure) and the
  integration rule (e.g. `no-pr` on a side branch), then dispatches via
  `/workbench:task-herdr`, **letting task-herdr author the exact prompt** from
  the item's intent + route + flags. It moves the item's block from
  `## Pending tasks` to `## Tasks` and records the spawn JSON.
- Then **relaunches** exactly one watcher in the background (no `--reset`).

The dispatch subagent never writes prompt prose itself - task-herdr is the single
owner of the spawned tab's prompt text.
