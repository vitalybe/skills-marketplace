---
name: use-worktree-branch
description: Make sure the current work is happening in a dedicated git worktree on its own branch, creating and switching into one if it is not. Carries dirty changes over with a stash/pop (never commits them), and if commits already landed on main/master it renames that branch into the worktree branch and recreates main from origin/main. Use whenever the user says "move this to a worktree", "put this on its own branch", "I'm on main again, fix it", "get me off master", "set up a worktree for this task", "isolate this work", or starts real work while sitting on the default branch. Also use as a preflight before implementing a task, so nothing accumulates on a shared branch.
---

# use-worktree-branch - get the work onto an isolated worktree branch

Ensure the current work lives in a linked git worktree on its own branch. If it
already does, stop - there is nothing to do. Otherwise create the worktree,
move the branch (and any commits already sitting on the default branch) into it,
carry the dirty working tree across, and leave the main checkout sitting clean on
the default branch at `origin/<default>`.

This skill never commits. Stashed changes are popped back, still uncommitted, in
the worktree - committing is the commit step's job, and the user may want
to keep working before then.

The skill runs inline (it changes directory), so do NOT run it in a fork. Running
inline is also what lets the pre-loaded state below capture the source checkout.

## Pre-loaded state

These blocks are captured at load time, in the directory this skill was invoked
from - the source checkout, before any worktree exists. Read them first; you
should not need to re-run these commands. Re-run one only if its block is empty
or errored, or to get fresh state after you stash, switch, or `cd`.

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

<default-branch-from-origin-head>
!`git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'`
</default-branch-from-origin-head>

<local-default-branch-candidates>
!`git branch --list --format='%(refname:short)' main master trunk 2>&1`
</local-default-branch-candidates>

<remote-default-branch-candidates>
!`git branch --remotes --list --format='%(refname:short)' origin/main origin/master origin/trunk 2>&1`
</remote-default-branch-candidates>

<upstream-of-current-branch>
!`git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>&1`
</upstream-of-current-branch>

<commits-ahead-of-upstream>
!`git log --oneline '@{upstream}..HEAD' 2>&1`
</commits-ahead-of-upstream>

<commits-ahead-of-origin-head>
!`git log --oneline refs/remotes/origin/HEAD..HEAD 2>&1`
</commits-ahead-of-origin-head>

<existing-branches>
!`git branch --format='%(refname:short)' 2>&1`
</existing-branches>

## 1. Read the surveyed state

Work from the blocks above:

- **Already in a linked worktree?** True when `<git-dir>` differs from
  `<git-common-dir>`.
- **Current branch** = `<current-branch>`.
- **Default branch** = `<default-branch-from-origin-head>`. If that is empty
  (`origin/HEAD` is not set in this clone), fall back to whichever of `main` /
  `master` / `trunk` appears in `<remote-default-branch-candidates>`. If both
  `main` and `master` exist remotely, or neither does, ask the user rather than
  guessing - picking wrong here resets the wrong branch.
- **Dirty?** `<status-short>` is non-empty.
- **Commits to carry** = `<commits-ahead-of-origin-head>` when the default came
  from `origin/HEAD`, otherwise `<commits-ahead-of-upstream>`. If both blocks
  errored (no upstream, no `origin/HEAD`), recompute once with
  `git log --oneline refs/remotes/origin/<default>..HEAD`.

## 2. Already in a worktree -> stop

If you are in a linked worktree, the environment is already what this skill
produces. Say so and stop. Do not create a second worktree, do not stash, do not
move anything.

The one exception worth flagging: if you are in a linked worktree but checked out
on the default branch (unusual), tell the user - they probably want a real branch
- but still do not restructure anything without their go-ahead.

## 3. Pick the branch name and worktree path

**Branch name.** If the current branch is already a real feature branch (not the
default), keep its name - it is already what the user chose. Only invent a name
when the work is sitting on the default branch:

- Derive a `kebab-case` slug describing the work.
- If a **task ID** exists - the user names one, a JIRA key is in play, a herdr
  task id is in context - prefix it: `<task-id>-<slug>`, e.g.
  `AIE-1234-add-token-refresh`. Never invent a task ID; only use one that really
  exists.
- Keep it short. If the name already appears in `<existing-branches>`, pick
  `<slug>-2` or ask - never clobber an existing branch.

**Worktree path.** If `<worktree-list>` shows the repo already keeps linked
worktrees somewhere, reuse that parent directory - matching the existing
convention beats inventing a new one. Otherwise default to a sibling of the
checkout, deliberately OUTSIDE the working tree so it never pollutes
`git status`: `<repo-parent>/<repo-name>-worktrees/<branch-name>`.

## 4. Stash the dirty working tree

If `<status-short>` is non-empty, stash everything including untracked files.
Stashes are repo-global, so the new worktree can pop the very same stash - this
is what lets uncommitted work travel across without a commit:

```bash
git stash push --include-untracked --message "use-worktree-branch/<branch-name>"
```

Do this before anything else that moves branches - `git switch` and
`git branch -m` behave unpredictably or refuse outright with a dirty tree.

Remember that you stashed; step 6 has to pop it.

## 5. Move the branch into a worktree

Three shapes, depending on what step 1 found. Pick one.

**A. On the default branch, with commits to carry.** The commits are real work
that landed on a shared branch by accident. Rename the branch instead of
resetting it - renaming keeps every commit reachable under the new name, so
nothing can be lost, and then the default branch is recreated fresh from the
remote:

```bash
git branch -m "<default>" "<branch-name>"
git switch -c "<default>" "origin/<default>"
git worktree add "<worktree-path>" "<branch-name>"
```

The rename carries HEAD with it, so the second command is what puts the main
checkout back on a clean default branch tracking the remote. The third then
attaches the renamed branch to its own worktree.

**B. On the default branch, no commits to carry.** Nothing to preserve - just
branch off the current HEAD:

```bash
git worktree add "<worktree-path>" -b "<branch-name>"
```

The main checkout stays on the default branch, untouched.

**C. On a non-default branch in the main checkout.** The branch is fine; it is
just not in a worktree. Git refuses to check a branch out in two places, so the
main checkout has to release it first:

```bash
git switch "<default>"
git worktree add "<worktree-path>" "<branch-name>"
```

If the default branch does not exist locally, use
`git switch -c "<default>" "origin/<default>"` instead.

## 6. Enter the worktree and restore the dirty changes

Move the **session** into the worktree with the `EnterWorktree` tool, passing the
worktree you just created as `path`:

```
EnterWorktree({ path: "<worktree-path>" })
```

A bare `cd` in Bash is not enough. It only moves the Bash tool's own directory -
the session stays pointed at the original checkout, so the worktree's `CLAUDE.md`,
memory, and plans never load and the user has to run `/cd` by hand. `EnterWorktree`
switches the session and refreshes those caches. Use `path` (never `name`): the
worktree already exists, and step 5 registered it in `git worktree list`, which is
what `path` requires.

If `EnterWorktree` is unavailable, fall back to `cd "<worktree-path>"` in Bash and
tell the user to run `/cd <worktree-path>` so their session follows.

If you stashed in step 4, restore it here:

```bash
git stash pop
```

On a conflict: stop, do not auto-resolve. Report the conflicting files and the
stash ref (`git stash list`) so the user can recover - the stash is still intact
after a failed pop, and silently merging someone's in-flight edits is exactly the
kind of thing that is impossible to unpick later.

## 7. Report

State plainly:

- The worktree path and branch, and whether the branch was created or renamed.
- If a branch was renamed: that the default branch was recreated at
  `origin/<default>`, and that the main checkout now sits there clean.
- Which commits travelled to the worktree branch (list them briefly).
- Whether dirty changes were stashed and popped, and any pop conflict.
- That **nothing was committed and nothing was pushed** - the changes are sitting
  uncommitted in the worktree, ready to work on or hand to
  the commit step.
- The worktree path, so the user knows where their editor should point.

## 8. Carry on with the task

This skill is usually a preflight, not the request. If the invocation arguments
describe actual work ("set up a worktree and then do X", or just X), that
description **is** the task - keep it and start on it in the worktree, in the same
turn, right after the report. Never end with "say the word and I'll start": the
user already said it, and stopping forces them to paste the whole request again.

Only stop after the report when the arguments asked for nothing beyond the
worktree setup, or when step 6's stash pop conflicted.

## Safety rules

- **Rename, never reset.** Moving commits off the default branch is done with
  `git branch -m` plus a fresh branch at `origin/<default>`. Never hard-reset a
  branch that has commits on it - the rename is equally short and cannot lose
  work.
- Stash before switching or renaming branches; never move branches with a dirty
  tree.
- Never commit. This skill sets up the workspace; the user decides when work is
  ready to record.
- Never `--force` a worktree add, never overwrite or delete an existing branch,
  never `git push`, `git rebase`, or `git commit --amend`.
- Never resolve a stash-pop conflict automatically; hand it back.
- Cleanup (merging the worktree back, removing it) belongs to
  `/devflow:_internal-step-close`.
