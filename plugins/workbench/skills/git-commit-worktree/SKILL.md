---
name: git-commit-worktree
description: Isolate the current work into a per-task git worktree, then commit it there with the git-commit skill. If you are already inside a linked worktree, it just runs git-commit in place. Otherwise it creates a worktree+branch slugged to the task (using the task ID when one is available), moves any local-only commits and dirty changes over to it, and commits there - leaving the source branch clean. Use when the user says "commit this into a worktree", "move this to a task worktree and commit", "graduate this work off main into its own branch and commit", or similar.
---

# git-commit-worktree - commit into a per-task worktree

Take whatever is on the current (shared) branch - local-only commits and/or a
dirty working tree - move it into a dedicated worktree+branch named after the
task, and commit it there with `/workbench:git-commit`. The source branch is
left clean, pointing back at its upstream base.

This skill runs inline (it changes directory and then delegates to the forked
`git-commit`), so it does NOT run in a fork itself. Running inline is also what
lets the pre-loaded state below capture the source checkout.

## Pre-loaded state

These blocks are captured at load time, in the directory this skill was invoked
from - the source checkout, before any worktree exists. Read them first; you
usually do not need to re-run these commands. Re-run one only if its block is
empty or errored, or to get fresh state after you stash, reset, or `cd`.

<toplevel>
!`git rev-parse --show-toplevel 2>&1`
</toplevel>

<git-dir>
!`git rev-parse --git-dir 2>&1`
</git-dir>

<git-common-dir>
!`git rev-parse --git-common-dir 2>&1`
</git-common-dir>

<current-branch>
!`git rev-parse --abbrev-ref HEAD 2>&1`
</current-branch>

<status-short>
!`git status --short 2>&1`
</status-short>

<worktree-list>
!`git worktree list --porcelain 2>&1`
</worktree-list>

<default-branch>
!`git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'`
</default-branch>

<base-against-origin-head>
!`git merge-base HEAD refs/remotes/origin/HEAD 2>/dev/null`
</base-against-origin-head>

<local-commits-ahead>
!`git rev-list --count refs/remotes/origin/HEAD..HEAD 2>/dev/null`
</local-commits-ahead>

## 1. Read the surveyed state

Work from the pre-loaded blocks above. Determine:

- **In a linked worktree?** True when `<git-dir>` differs from
  `<git-common-dir>`.
- **Current branch** = `<current-branch>` (the source branch).
- **Default branch** = `<default-branch>`; if empty (origin/HEAD isn't set),
  fall back to whichever of `main` / `master` exists
  (`git rev-parse --verify <name>`). If still ambiguous, ask.
- **Dirty?** `<status-short>` is non-empty.
- **Base** and **local commits to move** are pre-computed in
  `<base-against-origin-head>` and `<local-commits-ahead>` - but only trust
  those when `<default-branch>` was non-empty (they resolve against
  `origin/HEAD`). If the default branch came from the fallback, recompute both
  against `refs/remotes/origin/<default>` in step 3.

## 2. Already in a worktree -> just commit

If you are in a linked worktree, this skill's job is already done by the
environment. Invoke `/workbench:git-commit` in place and stop. Do not create
another worktree, stash, or move anything.

## 3. Decide the slug and base (main checkout only)

- **Slug.** Derive a `kebab-case` slug from the task (what the work is). If a
  **task ID** is available - the user names one, a JIRA key is in play, or a
  herdr task/tab id is in context - prefix it: `<task-id>-<slug>` (e.g.
  `AIE-1234-add-token-refresh`). Otherwise just `<slug>`. Never invent a task
  ID; only use one that actually exists. Keep it short.
- **Base.** The point the source branch should return to - where the local-only
  commits diverged. Use `<base-against-origin-head>` from the pre-loaded state;
  recompute with `git merge-base HEAD refs/remotes/origin/<default>` only if the
  default branch came from the fallback (see step 1).
- **Local commits to move?** `<local-commits-ahead>` > 0 (same caveat - recompute
  with `git rev-list --count <base>..HEAD` if the default came from the fallback).
- **Worktree location.** Reuse the parent directory of any existing linked
  worktree from `git worktree list` if the repo already keeps them somewhere.
  Otherwise default to a sibling of the checkout, OUTSIDE the working tree so it
  never shows up in `git status`: `<repo-parent>/<repo-name>-worktrees/<slug>`.

If the working tree is clean AND there are no local commits to move, there is
nothing to isolate - say so and stop (nothing to commit).

## 4. Stash dirty changes (if any)

If the working tree is dirty, stash everything including untracked so the source
checkout goes clean and the changes travel to the worktree. Stashes are
repo-global, so the new worktree can pop the same stash:

```bash
git stash push --include-untracked --message "git-commit-worktree/<slug>"
```

Remember that you stashed. Do this BEFORE any reset in step 6.

## 5. Create the worktree and branch

Create the worktree on a new branch starting at the current HEAD, so the new
branch carries the local-only commits:

```bash
git worktree add "<worktree-path>" -b "<slug>"
```

(`git worktree add ... -b` starts from HEAD by default.) If the branch name
already exists, pick `<slug>-2` (etc.) or ask - do not clobber an existing
branch.

## 6. Move the commits off the source branch

Only if step 3 found local commits to move:

- **When the source branch is the default branch** (the common case - work
  landed on `main` by accident), reset it back to the base so those commits now
  live only on the new worktree branch. The main checkout is clean at this point
  (you stashed in step 4) and the commits are safe on the new branch, so this
  loses nothing - but it rewrites the shared branch pointer, so **confirm with
  the user first**, then:

  ```bash
  git reset --hard "<base>"
  ```

- **When the source branch is not the default branch**, do not strip it
  silently - ask the user whether to reset it back to `<base>` or leave it as
  is. Default to asking.

If there were no local commits to move, skip this step entirely.

## 7. Enter the worktree and restore the dirty changes

```bash
cd "<worktree-path>"
```

The working-directory change persists across subsequent Bash calls. If you
stashed in step 4, restore it here (into the new worktree):

```bash
git stash pop
```

On a stash-pop conflict: stop, do not auto-resolve, report the conflicting
files and the stash ref so the user can recover.

## 8. Commit in the worktree

Invoke `/workbench:git-commit`. It operates on the current working directory,
which is now the worktree, so it commits the moved commits' companion changes
and the restored dirty changes there. After it returns, verify the commits
landed in the worktree, not the source checkout:

```bash
git -C "<worktree-path>" log --oneline -5
```

## 9. Report

State plainly:

- The worktree path and branch created, and the slug (and task ID) used.
- Whether local commits were moved, and that the source branch was reset back to
  `<base>` (or left as-is).
- Whether dirty changes were stashed and popped, and any pop conflict.
- What `git-commit` did (relay its report), including anything it left unstaged.
- That nothing was pushed.

## Safety rules

- **Confirm before `git reset --hard` on the source branch.** It is data-safe
  here (commits are on the new branch, dirty work is stashed), but it rewrites a
  shared branch pointer - never do it without the user's go-ahead.
- Stash BEFORE resetting; never `git reset --hard` with unstashed changes.
- Never `--force` a worktree add or branch operation; never overwrite an
  existing branch. Pick a new slug or ask.
- Never `git push`, `git rebase`, `git commit --amend`, or `--no-verify`.
- Never resolve stash-pop or merge conflicts automatically; hand them back.
- Cleanup (removing the worktree, merging it back) is `/workbench:git-merge-local`'s
  job, not this skill's.
