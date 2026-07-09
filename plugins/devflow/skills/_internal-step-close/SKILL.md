---
name: _internal-step-close
description: Close a development task by running validation and merging to main. Use after implementation is approved, or when the user invokes /devflow:_internal-step-close. Also trigger on phrases like "close the task", "merge this", "let's ship it", "wrap it up". This is the final phase of the dev task flow.
---

# Close

Covers two steps: validate and merge to main.

## General

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/flow-common-start.md`
</common-instructions>

## Step: Validation

- `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Starting validation"`

Run the project's full validation as specified below:

<validation-procedure>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/validation-procedure.md`
</validation-procedure>

If errors occur, fix them and re-run until all pass. Get user approval for fixes, then `git commit`.

- `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Validation passed"`

## Step: Merge to Main

- `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Starting session close"`
- `${CLAUDE_PLUGIN_ROOT}/bin/tasks set-state <KEY> Done`

### Detect environment

Determine whether the current checkout is a worktree or the main repo:

```bash
[ "$(git rev-parse --git-common-dir)" = "$(git rev-parse --git-dir)" ] && echo "main-repo" || echo "worktree"
```

### Pick merge strategy

Read `use-pull-requests` from `<project-config>` loaded in the common instructions above.

- If the key is missing: run the `/devflow:config-project` skill to set it, then re-read the config and continue.
- If `use-pull-requests = true` → **PR path**
- If `use-pull-requests = false` → **Direct merge path**

### PR path

- `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Pushing branch and opening PR"`
- Push the current branch: `git push -u origin HEAD`
- Open a PR with `gh pr create`. **PR title MUST contain `<KEY>`** so the
  task tracker auto-links the PR. (Task-less mode: no key exists - use a
  short imperative title derived from the plan slug instead.) The body
  should link to the plan file: `_plans/<KEY>-*.md` (task-less:
  `_plans/<slug>.md`).
- `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "PR opened: <url>"`
- Stop here. The human reviewer merges on GitHub. Do not merge locally.

### Direct merge path

- `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Merging to main"`

Run the project's integration script as specified below:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/integration-worktree-merge
```

- `${CLAUDE_PLUGIN_ROOT}/bin/tasks flow-progress-set <KEY> Done`
- `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Merged to main"`
