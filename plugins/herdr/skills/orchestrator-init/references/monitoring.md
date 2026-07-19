# Monitoring - the tracker and the monitoring subagent

Monitoring is split in two so the orchestrator's context stays clean:

- **`scripts/track-children.py`** - a one-shot tracker. It blocks until a
  *settled* change among the orchestrator's child agents, prints that change,
  and exits. It never loops inside the orchestrator.
- **The monitoring subagent** - a fresh `general-purpose` Agent per cycle that
  runs the tracker, updates the status doc, and returns a short summary. The
  orchestrator re-spawns it each cycle. The orchestrator itself never polls.

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

## The monitoring subagent

Spawn one fresh `general-purpose` Agent **per cycle**, in the background. Give it
the orchestrator's pane id and the target-doc path. Reusable prompt:

```
You are the monitoring subagent for an orchestration session. Do NOT touch any
task worktree or code. One cycle only, then report back and exit.

1. Run the tracker (it blocks until a settled change, then exits):
     ${CLAUDE_PLUGIN_ROOT}/skills/orchestrator-init/scripts/track-children.py --parent <ORCH_PANE>
2. Read its JSON output (also at /tmp/herdr-monitoring/latest.json). For every
   child whose "to" is "blocked" or "done", read that pane to get the gate
   question / result:
     herdr pane read <pane> --source recent
3. Edit the status doc at <TARGET_PATH> to current state, following
   ${CLAUDE_PLUGIN_ROOT}/skills/orchestrator-init/references/status-doc-format.md - update
   the changed tasks' status lines and any open questions. Current-state voice;
   never write "was X now Y".
4. Return a CONCISE summary and stop: for each changed task, "<name>: <old> ->
   <new>", and list any open questions / blocked gates that need an
   orchestrator decision or a reply to the tab. Nothing else - no narration.
```

Substitute `<ORCH_PANE>` (your `$HERDR_PANE_ID`) and `<TARGET_PATH>` (from the
`orchestrator-target` pointer file).

When the subagent returns, act on anything actionable, then spawn the next cycle.
To reply to / steer / stop a blocked tab, use `/herdr:task-herdr`'s
`scripts/herdr-io.sh` (`send` / `stop`) - that is orchestrator work, not the
monitor's.
