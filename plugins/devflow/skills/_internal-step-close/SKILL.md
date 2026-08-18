---
name: _internal-step-close
description: Close a development task by running validation and merging to main. Use after implementation is approved, or when the user invokes /devflow:_internal-step-close. Also trigger on phrases like "close the task", "merge this", "let's ship it", "wrap it up". This is the final phase of the dev task flow.
---

# Close

Covers two steps: validate and merge to main.

User input goes through gates - see **Gates** in the common instructions
below.

## General

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/flow-common-start.md`
</common-instructions>

## Step: Validation

Run the project's full validation as specified below (the project's own
`docs/validation-procedure.md` when it has one, else the plugin fallback):

<validation-procedure>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec docs/validation-procedure.md --fallback ${CLAUDE_PLUGIN_ROOT}/docs/validation-procedure.md`
</validation-procedure>

If errors occur, fix them and re-run until all pass. Get user approval for fixes, then `git commit`.

## Step: Merge to Main

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

- Push the current branch: `git push -u origin HEAD`
- Open a PR with `gh pr create`. **PR title MUST contain `<KEY>`** so the
  task tracker auto-links the PR. (Task-less mode: no key exists - use a
  short imperative title derived from the plan slug instead.) The PR body's
  first line is a link to the plan:

  `Plan: <repo-url>/blob/<head-branch>/<plan-path>`

  Build `<repo-url>` from `git remote get-url origin`, normalized to https
  form with any `.git` suffix stripped (e.g.
  `git@github.com:drivenets/ai-enablement.git` becomes
  `https://github.com/drivenets/ai-enablement`). `<head-branch>` is the
  branch the PR is opened from. `<plan-path>` is the injected `<plan-path>`.
  Example:

  `Plan: https://github.com/drivenets/ai-enablement/blob/throughput-vs-cost-AIE-401/_plans/AIE-401-throughput-vs-cost.md`
- `${CLAUDE_PLUGIN_ROOT}/bin/tasks set-state <KEY> "Pending Pull Request Review"`
  (if the project's Jira has no such state, use `"In Review"`).
- Stop here. The human reviewer merges on GitHub. Do not merge locally.
- Report completion: the PR url.

### Direct merge path

- Merge locally: `${CLAUDE_PLUGIN_ROOT}/bin/git-merge-me-local`
- If this checkout is a worktree, remove it with plain git once the merge
  succeeds: from the main checkout, `git worktree remove <path>`, then
  `git branch -d <branch>` (only if fully merged; report instead of forcing).
- `${CLAUDE_PLUGIN_ROOT}/bin/tasks set-state <KEY> Done`
- Report completion: merged to main.
