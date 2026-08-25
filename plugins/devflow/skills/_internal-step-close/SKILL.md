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

Determine whether the current checkout is a worktree or the main repo - it
prints `main-repo` or `worktree`:

```bash
${CLAUDE_PLUGIN_ROOT}/bin/worktree-kind
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

  The body's last line records the devflow version that produced the PR:

  `devflow v<version>`, where `<version>` is
  `jq -r .version "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"`.
- `${CLAUDE_PLUGIN_ROOT}/bin/tasks set-state <KEY> "Pending Pull Request Review"`
  (if the project's Jira has no such state, use `"In Review"`).
- Stop here. The human reviewer merges on GitHub. Do not merge locally.
- Report completion: the PR url.

### Direct merge path

- Merge locally: `${CLAUDE_PLUGIN_ROOT}/bin/git-merge-me-local`
- If this checkout is a worktree, remove it once the merge succeeds - see
  **Removing the worktree** below.
- `${CLAUDE_PLUGIN_ROOT}/bin/tasks set-state <KEY> Done`
- Report completion: merged to main.

## Removing the worktree

Only after the merge succeeded.

1. **Leave it first.** A session isolated in the worktree cannot run git
   against the main checkout - every such command is refused, and the script
   below refuses too. Call `ExitWorktree({ action: "keep" })` (load it with
   `ToolSearch` if needed); `keep` because step 2, not the tool, is what
   deletes it.
2. **Remove it:**

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/bin/worktree-remove <path>
   ```

   Report what it printed. If it refuses, relay that rather than forcing past
   it.
