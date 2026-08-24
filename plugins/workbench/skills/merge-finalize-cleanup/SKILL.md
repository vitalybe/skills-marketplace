---
name: merge-finalize-cleanup
description: Land the current branch and clean up after it - picks the right route automatically (GitHub PR self-merge, or a local no-ff merge when there is no GitHub or pushing straight to the default branch is allowed), then removes the worktree it ran from. Use whenever the user wants a finished branch landed - "merge my PR", "self-merge", "merge this branch", "land this", "ship it", "finalize and clean up", "wrap up this worktree". Creates the PR when none exists, enables auto-merge, polls until it merges or CI fails, then removes the worktree and deletes the branch. Refuses to run from the default branch or a detached HEAD.
---

# merge-finalize-cleanup

Land the current branch, then clean up the worktree it ran from. Two routes:
via a GitHub PR when the default branch is protected, or a plain local `--no-ff`
merge when it isn't. The pre-loaded blocks below tell you which.

## Pre-loaded state

Captured at load time, in the directory this skill was invoked from. Read these
first - the survey is already done. Re-run one only if its block is empty or
errored, or to get fresh state after you act.

<ruleset-check-main>
!`gh ruleset check main 2>&1`
</ruleset-check-main>

<current-branch>
!`git rev-parse --abbrev-ref HEAD 2>&1`
</current-branch>

<default-branch>
!`gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'`
</default-branch>

<pr-state>
!`gh pr view --json number,state,url,baseRefName 2>&1`
</pr-state>

<toplevel>
!`git rev-parse --show-toplevel 2>&1`
</toplevel>

<worktree-list>
!`git worktree list --porcelain 2>&1`
</worktree-list>

<status-short>
!`git status --short 2>&1`
</status-short>

## 1. Pick the route

Read `<ruleset-check-main>`:

- **PR route** - the output lists a `pull_request` or `required_status_checks`
  rule. The default branch is gated; the change has to go through a PR. Continue
  at §2.
- **Local route** - anything else: `gh` errored (not a GitHub repo, no remote,
  `gh` missing or unauthenticated), or rules apply but none of them gate pushes
  (e.g. only `deletion` / `non_fast_forward`). Pushing to the default branch is
  allowed, so there is no reason to open a PR.

  On the local route, hand the whole job to `/workbench:git-merge-local` - it
  does the merge *and* the worktree cleanup - and stop here. Report what it did.

If `<default-branch>` is not `main`, `<ruleset-check-main>` checked the wrong
branch: re-run `gh ruleset check <default-branch>` before deciding.

Stop and report instead of continuing when `<current-branch>` is the default
branch or `HEAD` (detached) - there is nothing to land.

## 2. PR route - land it

Commit anything pending first. If `<status-short>` is non-empty, follow the
repo's commit conventions (see its `CLAUDE.md` and `git log --oneline -5`), and
write the message to `/tmp/claude-<epoch-ms>.md` with the Write tool and
`git commit -F` it - never heredocs / `echo` / `$()`. Don't commit anything that
looks like a secret; ask when unsure whether an untracked file belongs.

Then run the bundled script, which creates the PR if `<pr-state>` shows none,
rebases onto the base branch and force-pushes, enables auto-merge, and polls
until the PR merges:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/merge-finalize-cleanup/pr-land.sh
```

This blocks until the PR lands or CI fails, which can take many minutes: run it
**in the background** and report the outcome rather than waiting idle.

Tunables: `PR_LAND_POLL_INTERVAL` (default 3s), `PR_LAND_TIMEOUT` (default
1800s).

The script is the source of truth for this route. If the flow needs to change,
edit the script - don't reimplement it in the conversation.

If it exits non-zero, stop: report the failure (rebase conflict, CI failure,
closed PR, timeout) and leave the worktree alone. Do not retry blindly.

## 3. Clean up the worktree

Only after the branch is actually merged (the script exited 0, or the local
route reported a merge commit).

`<worktree-list>` gives the main checkout root on its first `worktree ` line. If
`<toplevel>` equals that root, this is not a linked worktree - skip to §4.

Otherwise, from the linked worktree:

1. `cd` to the main checkout root **first** - removing the worktree you are
   standing in leaves the shell in a deleted directory.
2. Confirm it is on the default branch and clean. If not, stop and report -
   never switch branches or stash there.
3. `git pull --ff-only` so the merge commit is local.
4. `git worktree remove <worktree-path>` - no `--force`. If it refuses because
   of leftover files, report instead of forcing.
5. `git branch -d <branch>`. If git says the branch isn't merged (the PR was
   squashed, so its commits aren't ancestors), confirm the PR state is `MERGED`
   and then use `git branch -D`.
6. Do not delete the remote branch - GitHub's auto-delete or the user handles it.

## 4. Report

- The route taken, and why (one line from the ruleset check).
- The PR (number + URL) and how it merged, or the local merge commit.
- Worktree removed and branch deleted, or why it was skipped.
- On the local route only: nothing was pushed, so the default branch is ahead of
  its remote locally.

## Safety rules

- Never `git reset --hard`, `git commit --amend`, or `--no-verify`.
- Never resolve rebase or merge conflicts automatically - hand them back.
- Never force a worktree removal or a `git branch -D` on an unmerged branch
  without confirming the PR merged.
- Never delete a remote branch.
