---
name: task-herdr
description: Delegate a dev task by spawning it as a real `claude` agent in its own tracked herdr tab, instead of an Agent-tool subagent. Use when running inside herdr (HERDR_ENV=1) and the user wants a task run in a visible, tracked tab they can watch or talk to - phrases like "spawn this in a herdr tab", "run it as a tracked tab", "do this the herdr way", or when running several such agents in parallel and monitoring them together. If HERDR_ENV is not 1, fall back to normal Agent-tool subagents (see `/herdr:orchestrate-agents`).
---

# task-herdr - run a task in a tracked herdr tab

Spawn a task as a full interactive `claude` in its own dedicated herdr tab. The
agent is a real, visible terminal the user can watch or type into; herdr tracks
its `agent_status` (`herdr agent list` / `herdr agent get <root_pane>`), and many
tabs can be monitored in parallel.

## Prerequisite

Check `HERDR_ENV=1`. If it is not set, say you are not inside herdr and fall
back to normal Agent-tool subagents (see `/herdr:orchestrate-agents`) - do not use this skill.

## Opening a task

1. **Generate a slug and title** - a short descriptive kebab-case branch slug
   (for a tracker task, append the key, e.g. `mock-scenario-dropdown-AIE-370`).
   The **title must be under 30 characters** - herdr uses it directly as the
   agent's name (the script caps it defensively at 29 chars).

2. **Write the task prompt to a temp file** (e.g. under your scratchpad or
   `/tmp`). Include that the agent must work only inside its worktree.

3. **Spawn with one call** - it creates the worktree+branch, opens a dedicated
   tab (`herdr tab create`), launches the agent in it (`herdr agent start
   --tab`, cd'd into the worktree, claude started interactive with the prompt as
   its positional arg), closes the tab's leftover root shell, and registers the
   agent under the orchestrator for tracking (`herdr agent set-parent`). Placement
   and parenting are two calls because `agent start --parent` would split the
   orchestrator's pane in the same tab instead of opening a new one:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/task-herdr/scripts/spawn-herdr-task.sh \
     --slug <slug> --title "<title>" --prompt-file <tmpfile>
   ```

   It prints a JSON summary (`slug`, `title`, `worktree`, `branch`,
   `workspace`, `tab_id`, `tab_label`, `root_pane`, `prompt_file`, `parent`).
   Capture it - you need `root_pane` to monitor and `tab_id`/`worktree` to
   clean up. Optional flags: `--base` (default `origin/main`), `--parent`
   (default `$HERDR_PANE_ID`, the current herdr pane), `--workspace`.

### Talking to / stopping a tab

Send messages through the idle-guarded helper, never a bare
`herdr pane send-text` + `send-keys` - typing into a working agent
queues/garbles the input:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/task-herdr/scripts/herdr-io.sh send <pane> --file <msg-file>
```

`send` runs the same stable `wait-idle` first, then types the message and
presses Enter; if the agent never settles within the timeout it refuses
(`--force` injects anyway). To deliberately interrupt a working agent:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/task-herdr/scripts/herdr-io.sh stop <pane>   # send Escape
```

## Cleanup

When a task's work is done: remove the worktree, close the tab
(`herdr tab close <tab_id>`), and sync `main`.
