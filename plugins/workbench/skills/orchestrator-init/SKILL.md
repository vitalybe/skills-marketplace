---
name: orchestrator-init
description: Initialize an orchestration session's live status document (the "target") and keep it current. Use at the START of any orchestration/multi-task session - whenever the user says things like "start an orchestration session", "orchestrate these tasks", "here's the status doc / target", "track everything in this doc", or "we'll open several tasks and monitor them". Also use whenever the user hands over a markdown file to serve as the session's status target. If a session is about to run several tasks in parallel and no status target is established yet, invoke this skill.
---

# orchestrator-init - establish the session status doc

An orchestration session runs several tasks in parallel (via `/workbench:orchestrate-agents`
subagents and/or `/workbench:task-herdr` tabs). This skill sets up the single markdown
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

## 3. Keep it live - via a monitoring subagent

You (the orchestrator) do **not** poll panes or hand-edit the doc during the
session. Monitoring, reading the monitor output, and writing/editing the target
doc are delegated to a **monitoring subagent** so that noise (every poll, every
pane read, every doc edit) stays out of your context. You are made aware only of
**what changed** - child status transitions, new/finished tasks, open questions,
blocked gates - and act on those.

Each monitoring **cycle** is one fresh subagent (spawn it in the background with
the Agent tool, `general-purpose`). The cycle:

1. Runs the tracker once - it blocks until a **settled change**, persisting
   state in `/tmp/herdr-monitoring/` so the next cycle continues seamlessly:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/orchestrator-init/scripts/track-children.py --parent <YOUR_PANE>
   ```

   `<YOUR_PANE>` is the orchestrator's `$HERDR_PANE_ID` - the pane whose child
   agents are the tracked tasks. See
   [references/monitoring.md](references/monitoring.md) for the tracker's
   behaviour (20s steady poll, 5s parallel per-child debounce, 60s max, exit on
   a settled status/membership change).

2. Reads the change report (the tracker's stdout / `/tmp/herdr-monitoring/latest.json`).
   For any child that went `blocked` or `done`, reads that pane
   (`herdr pane read <pane> --source recent`) to pull out the GATE question /
   result.

3. Edits the target doc to current state per
   [references/status-doc-format.md](references/status-doc-format.md) - task
   status lines and open questions. Current-state voice; no "was X now Y".

4. Returns a **concise** summary to you: which tasks changed state, plus any open
   questions / blocked gates that need a decision or a reply. Nothing else.

When a cycle returns, you: handle anything actionable (reply to / steer / stop a
blocked tab, open follow-up tasks, surface a decision to the user), then **spawn
the next monitoring cycle** to continue. If nothing is actionable, just spawn the
next cycle. A ready-to-use subagent prompt is in
[references/monitoring.md](references/monitoring.md).

## Pointers

- Doc structure and line format: [references/status-doc-format.md](references/status-doc-format.md).
- The tracker + monitoring-subagent contract: [references/monitoring.md](references/monitoring.md).
- Opening the tasks themselves, and interacting with a tab (send / stop): `/workbench:orchestrate-agents` / `/workbench:task-herdr`.
