---
name: task-herdr
description: Delegate a dev task by spawning it as a real `claude` agent in its own tracked herdr tab, instead of an Agent-tool subagent. Use when running inside herdr (HERDR_ENV=1) and the user wants a task run in a visible, tracked tab they can watch or talk to - phrases like "spawn this in a herdr tab", "run it as a tracked tab", "do this the herdr way", or when running several such agents in parallel and monitoring them together. If HERDR_ENV is not 1, fall back to normal Agent-tool subagents (see `/workbench:orchestrate-agents`).
---

# task-herdr - run a task in a tracked herdr tab

Spawn a task as a full interactive `claude` in its own dedicated herdr tab. The
agent is a real, visible terminal the user can watch or type into; herdr tracks
its `agent_status` (`herdr agent list` / `herdr agent get <root_pane>`), and many
tabs can be monitored in parallel.

## Prerequisite

Check `HERDR_ENV=1`. If it is not set, say you are not inside herdr and fall
back to normal Agent-tool subagents (see `/workbench:orchestrate-agents`) - do not use this skill.

## This skill owns the prompt text

`spawn-herdr-task.sh` launches `claude` with whatever prompt file it is handed.
To keep every spawned tab consistent, **this skill is the single owner of the
exact prompt text.** A caller - a user, or an orchestrator / task-creator
(`/workbench:orchestrate-agents`, `/workbench:orchestrator-init`) - supplies only
the task *intent* plus a few flags and follows the template below; callers do NOT
hand-author their own prompt prose.

The spawned agent runs its task through the **devflow** plugin, which decides how
much process the task needs (a trivial change is fast-pathed; a feature runs the
full requirements -> plan -> code -> close flow). task-herdr does not make that
call and does not embed route logic - it just tells the agent to run devflow.

Inputs a caller provides:

| Input | Meaning |
|-------|---------|
| **intent** | 1-2 sentences on what to build, plus any spec links (e.g. a Claude Design URL). |
| **base** | base branch (default `origin/main`). |
| **integration** | `pr` (let devflow run through its close phase) or `no-pr` (side branch: stop before close, integrate separately). |
| **tracker key** | optional; if absent, devflow runs **task-less**. |
| **route override** | optional; omit to let devflow triage. Set `fast path` or `full flow` only to force devflow's route. |
| **tab number** | optional ordinal for the tab label. An orchestrator passes the next number from its counter so tabs read `T<n> - <Name>` by spawn order; a standalone caller omits it. |

## Writing the prompt (the template)

Write the prompt to a temp file (scratchpad or `/tmp`), assembling the blocks
below. Include only the blocks that apply.

**1. Worktree preamble (always):**

```
You are a dev agent working ONLY inside your own git worktree (the directory you
were started in). Do not touch any other worktree, branch, or the parent repo.
```

**2. Task (always):** a `## Task` heading with the intent and any spec links.

**3. Design pointer (only if the intent references a `claude.ai/design` URL):**

```
This task references a Claude Design spec. Read it with the built-in DesignSync
tooling (see the `claude-design` skill) - do NOT WebFetch the URL or open it in
a browser.
```

**4. Run devflow (always):**

```
## Run this through the devflow
Drive this task with the devflow plugin: invoke `/devflow:start-flow`. It will
triage the task and either fast-path a trivial change or run the full
requirements -> plan -> code (with sub-agent code review) flow. Run TASK-LESS
(there is no tracker key). Requirements/plan gates are interactive - ask your
questions and wait for answers. If you cannot reach a spec, or an endpoint the
work needs does not exist, STOP and ask rather than guessing.
```

- Omit the "TASK-LESS" sentence when a tracker key was provided.
- If a **route override** was given, add one line: "Use the fast path." or
  "Run the full flow (all phases)."

**5. Integration block:**

- `no-pr`:
  ```
  ## STOP before the close phase (NO PR, NO merge)
  This work lives on a side branch and is integrated WITHOUT a PR by a separate
  process. Run through code and make the review pass clean, then COMMIT on this
  branch and STOP (go idle). Do NOT run the close phase, do NOT open a PR, do NOT
  merge, do NOT push. Integration happens outside this task.
  ```
- `pr`: no extra block - let devflow run through its close phase normally.

**6. Gate instruction (always):** end with a line telling the agent that if it
hits a real decision that is not its to make, or cannot reach a spec, it should
STOP and ask rather than guess.

## Opening a task

1. **Generate a slug and title** - a short descriptive kebab-case branch slug
   (for a tracker task, append the key, e.g. `mock-scenario-dropdown-AIE-370`).
   The **title must be under 30 characters** - herdr uses it directly as the
   agent's name (the script caps it defensively at 29 chars). Do NOT put a
   `T<n> -` prefix in the title; the ordinal goes to `--tab-number` (below), which
   prefixes the tab label only and leaves the agent name clean.

2. **Write the prompt to a temp file** per the template above.

3. **Spawn with one call** - it creates the worktree+branch, opens a dedicated
   tab (`herdr tab create`), launches the agent in it (`herdr agent start
   --tab`, cd'd into the worktree, claude started interactive with the prompt as
   its positional arg), closes the tab's leftover root shell, and registers the
   agent under the orchestrator for tracking (`herdr agent set-parent`). Placement
   and parenting are two calls because `agent start --parent` would split the
   orchestrator's pane in the same tab instead of opening a new one:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/task-herdr/scripts/spawn-herdr-task.sh \
     --slug <slug> --title "<title>" --prompt-file <tmpfile> [--tab-number <n>]
   ```

   Pass `--tab-number <n>` when a caller supplied a tab number, so the tab is
   labeled `T<n> - <title>`. The prefix lands on the **tab label** only; the
   herdr agent name stays the raw title so tracker reports read cleanly.

   It prints a JSON summary (`slug`, `title`, `worktree`, `branch`,
   `workspace`, `tab_id`, `tab_label`, `root_pane`, `prompt_file`, `parent`).
   Capture it - you need `root_pane` to monitor and `tab_id`/`worktree` to
   clean up. Optional flags: `--base` (default `origin/main`), `--parent`
   (default `$HERDR_PANE_ID`, the current herdr pane), `--workspace`.

### Talking to / stopping a tab

**Send messages with the `SendMessage` tool, not by typing into the pane.** A
spawned tab is a real `claude` session started with `--name "<title>"`, so it is
a peer you can message directly. Delivery is queued and drained by the receiver -
no idle guard, no race with a working agent, no garbled keystrokes.

Addressing (the herdr agent name IS the SendMessage name):

1. Take the agent's **name** from the spawn JSON (`title`) or from
   `herdr agent list` / `herdr agent children`.
2. Call `ListAgents` to get that name's ` [ref]`. A peer that is not already in
   your conversation is refused on the bare name - the error itself hands you the
   ref, so re-sending with it is fine too.
3. `SendMessage({to: "<title> [<ref>]", message: "..."})`.

Two things `SendMessage` cannot do, which still go through the pane:

- **A numbered-option gate** (`AskUserQuestion`). A message sent to an agent
  sitting on the picker is queued as its *next* prompt - the picker stays open
  and unanswered. Answer it with the keystroke:
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/skills/task-herdr/scripts/herdr-io.sh send <pane> --text "<n>" --force
  ```
- **Interrupting a working agent**:
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/skills/task-herdr/scripts/herdr-io.sh stop <pane>   # send Escape
  ```

Reading and polling stay with herdr as well: `herdr pane read <pane> --source
recent`, `herdr agent children`, `herdr-io.sh status <pane>`.

A tab spawned before this skill set `--name` will not appear under its title in
`ListAgents`; fall back to `herdr-io.sh send <pane>` for that one.

## Cleanup

When a task's work is done: remove the worktree, close the tab
(`herdr tab close <tab_id>`), and sync `main`.

## Common mistakes

- **Typing into the pane for ordinary messages.** Use `SendMessage`; the pane is
  for option-picker keystrokes and Escape only.
- **Answering a numbered-option gate with `SendMessage`.** The message queues
  behind the picker and gets read as the *next* prompt after someone else clears
  it - the gate itself stays open. Send the option number as a keystroke:
  `herdr-io.sh send <pane> --text "<n>" --force` (`--force` skips the idle wait; a
  gate-blocked agent reports `blocked` and never goes idle). Re-read the pane
  first - a tab in auto mode may have cleared the gate already.
- **Fetching a Claude Design spec with WebFetch or a browser.** Those hit an auth
  wall and render empty. Read the spec with the built-in DesignSync tooling - see
  the `claude-design` skill.
