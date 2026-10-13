---
name: _internal-step-close
description: Close a development task by running validation and merging to main. Use after implementation is approved, or when the user invokes /devflow:_internal-step-close. Also trigger on phrases like "close the task", "merge this", "let's ship it", "wrap it up". This is the final phase of the dev task flow.
allowed-tools: Bash(/*/skills/_devflow-shared/bin/mdexec *), mcp__dn-mcp-server__atlassian_jira_get_issue, mcp__dn-mcp-server__atlassian_jira_get_transitions, mcp__dn-mcp-server__atlassian_jira_transition_issue, mcp__plugin_aie-devflow_dn-mcp-server__atlassian_jira_get_issue, mcp__plugin_aie-devflow_dn-mcp-server__atlassian_jira_get_transitions, mcp__plugin_aie-devflow_dn-mcp-server__atlassian_jira_transition_issue
---

# Close

Covers three steps: validate, reconcile the plan with what was built, and
merge to main.

User input goes through gates - see **Gates** in the common instructions
below.

## General

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/docs/flow-common-start.md || /home/agent/.cursor/skills/_devflow-shared/bin/mdexec /home/agent/.cursor/skills/_devflow-shared/docs/flow-common-start.md`
</common-instructions>

## Step: Validation

Run the project's full validation as specified below (its own
`docs/validation-procedure.md` if it has one, else the bundled fallback):

<validation-procedure>
!`${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/bin/mdexec docs/validation-procedure.md --fallback ${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/docs/validation-procedure.md || /home/agent/.cursor/skills/_devflow-shared/bin/mdexec docs/validation-procedure.md --fallback /home/agent/.cursor/skills/_devflow-shared/docs/validation-procedure.md`
</validation-procedure>

Fix any errors and re-run until all pass. Get user approval for fixes, then `git commit`.

## Step: Reconcile the plan

Implementation drifts from the plan, and the reviewer reads the plan linked
from the PR. Bring it back in line first.

1. Read the plan at `<plan-path>` and the branch's full diff against main
   (`git diff main...HEAD`) - not your memory of the session.
2. Update the plan to describe what was actually built: rewrite drifted steps,
   add unplanned work, drop what was abandoned, fix stale paths and names.
   Keep its structure.
3. Be thorough: when this step is done, nothing in the plan may be stale,
   wrong, or no longer relevant.
4. Commit the plan alone. Change no code - raise a real implementation gap
   with the user instead of patching it here.

## Step: Merge to Main

### Detect environment

Determine whether this checkout is a worktree or the main repo - it prints
`main-repo` or `worktree`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/bin/worktree-kind || /home/agent/.cursor/skills/_devflow-shared/bin/worktree-kind
```

### Pick merge strategy

Read `use-pull-requests` from the `<project-config>` loaded above.

- If the key is missing: run the `/devflow:config-project` skill to set it, then re-read the config and continue.
- If `use-pull-requests = true` → **PR path**
- If `use-pull-requests = false` → **Direct merge path**

### PR path

- Push the current branch: `git push -u origin HEAD`
- Open a PR with `gh pr create`. **PR title MUST contain `<KEY>`** so the
  task tracker auto-links the PR. (Task-less mode: no key exists - use a
  short imperative title from the plan slug.) The body's first line links
  the plan:

  `Plan: <repo-url>/blob/<head-branch>/<plan-path>`

  Build `<repo-url>` from `git remote get-url origin` as https, without the
  `.git` suffix (`git@github.com:drivenets/ai-enablement.git` becomes
  `https://github.com/drivenets/ai-enablement`). `<head-branch>` is the PR's
  source branch; `<plan-path>` is the injected one. Example:

  `Plan: https://github.com/drivenets/ai-enablement/blob/throughput-vs-cost-AIE-401/_plans/AIE-401-throughput-vs-cost.md`

  The body's last line records the devflow version that produced the PR:

  `devflow v<version>`, where `<version>` is
  `jq -r .version "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"`.
  That manifest is the one file this skill reads outside `skills/`, so it is
  absent in a marketplace-provisioned pod. When the version cannot be read,
  omit the `devflow v<version>` line entirely - never write a bare `devflow v`.
- Transition the issue to "Pending Pull Request Review" - the procedure is in
  `_devflow-shared/docs/jira-tools.md`, inlined in the common instructions
  above. If the project's Jira has no such state, use `"In Review"`.
- Stop here. The human reviewer merges on GitHub. Do not merge locally.
- Report completion: the PR url.

### Direct merge path

- Merge locally: `${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/bin/git-merge-me-local || /home/agent/.cursor/skills/_devflow-shared/bin/git-merge-me-local`
- If this checkout is a worktree, remove it once the merge succeeds - see
  **Removing the worktree** below.
- Transition the issue to "Done" - see `_devflow-shared/docs/jira-tools.md`.
- Report completion: merged to main.

## Removing the worktree

Only after the merge succeeded.

1. **Leave it first.** A session isolated in the worktree cannot run git
   against the main checkout - every such command is refused, and so is the
   script below. Call `ExitWorktree({ action: "keep" })` (load it with
   `ToolSearch` if needed); `keep` because step 2 does the deleting.
2. **Remove it:**

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/bin/worktree-remove <path> || /home/agent/.cursor/skills/_devflow-shared/bin/worktree-remove <path>
   ```

   Report what it printed. If it refuses, relay that rather than forcing past
   it.
