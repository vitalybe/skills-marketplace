# Environment details

<current-branch>
!`git branch --show-current`
</current-branch>

<project-config>
!`cat project-config.toml 2>/dev/null || echo [[Error: No project config found in project root. Run: /devflow:config-project skill]]`
</project-config>

## Issue details

<issue-details>
!`${CLAUDE_PLUGIN_ROOT}/bin/tasks show || echo [[No issue key resolved from branch name]]`
</issue-details>

**Task mode vs task-less.** Run in **task mode** when a tracker key is in
play, detected either way:

- the **Issue details** block above shows a resolved issue (the branch
  or worktree name contained a key). If it instead shows *No issue key
  resolved*, the branch has no key; or
- the user names Jira explicitly - provides a key (`${CLAUDE_PLUGIN_ROOT}/bin/tasks show
  <KEY>`), or asks to create an issue (create it, then use its key).

Otherwise run **task-less**: proceed without tracker integration. Don't
stop, and don't ask about task tracking unless the user brings up Jira/a
task.

- **Task-less mode:** skip every `${CLAUDE_PLUGIN_ROOT}/bin/tasks` call in the devflow
  skills - `comment`, `set-state`, `flow-progress-set`,
  `flow-progress-get`. Everything else in the flow behaves identically.
  (The dispatcher also no-ops these safely when no key resolves, so a
  stray call is harmless - but don't rely on it, just skip.)
- (Task mode) If issue state is not Done/Cancelled - update it: `${CLAUDE_PLUGIN_ROOT}/bin/tasks set-state <KEY> "In Progress"`
- (Task mode) If the issue has a parent, fetch that too: `${CLAUDE_PLUGIN_ROOT}/bin/tasks show <PARENT-KEY>`

## Plan file path

<plan-path>
!`${CLAUDE_PLUGIN_ROOT}/bin/tasks plan || echo [[No plan path resolved - task-less mode]]`
</plan-path>

The path above is the plan file for this task - existing if one is
already in the tree (or on the task's branch), else the canonical path
to create. devflow-* skills use this directly; **do not** re-run
`tasks plan` to recompute it.

**Task-less mode:** if the block above contains an error instead of a
path, derive the path once yourself - `_plans/<slug>.md`, kebab-cased
from the task summary (~50 chars) - and use it exactly as you would the
injected path.

## Talking to the task tracker

All task-tracker operations go through `${CLAUDE_PLUGIN_ROOT}/bin/tasks`. The script
reads `task-system` from `project-config.toml` and dispatches
internally - never invoke the underlying CLI from a SKILL.md directly.
In task-less mode this whole table is skipped (see above).

```bash
tasks show              [KEY]                       # issue details
tasks comment           [KEY] (BODY | --from-file P) # post a comment
tasks set-state         [KEY] STATE                  # transition status
tasks flow-progress-get [KEY]                       # current phase or ""
tasks flow-progress-set [KEY] PHASE                 # advance phase
tasks plan              [KEY] [TITLE]               # existing plan (tree/branch) or canonical new path
```

Canonical phases: `Requirements`, `Plan`, `Code`, `Done`.

### Posting issue comments

```bash
${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Comment text"
# Multiline:
${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> --from-file /tmp/claude-<epoch>.md
```

### Where plans live

Plans live in `_plans/<KEY>-<slug>.md` (task-less: `_plans/<slug>.md`) -
not in the issue description. See
`${CLAUDE_PLUGIN_ROOT}/docs/plan-formats.md` for the full convention
(location, naming, plan format, cross-task / cross-branch lookup).

### Claude Code Task Tracking

Use Claude Code Tasks to track the steps in this workflow.
