---
name: git-merge-local
description: Merge the current branch into the repo's default branch locally with a --no-ff merge commit. If run from a linked git worktree, it also commits pending changes, merges the worktree branch into the default branch in the main checkout, then removes the worktree and deletes the branch. Use when the user says "merge this locally", "merge no-ff and clean up the worktree", "finish/land this worktree", "merge my branch into master locally", or similar. Does not push and does not build.
---

# Local no-ff merge (with optional worktree cleanup)

Land the current branch into the repo's default branch with a `--no-ff` merge, entirely locally. Behavior depends on whether you are in a linked worktree.

Never `git push` and never build as part of this skill. Report at the end that nothing was pushed.

## 1. Survey state

Run these together:

```bash
git rev-parse --show-toplevel
git rev-parse --abbrev-ref HEAD
git status --short
git worktree list --porcelain
```

Determine:

- **Current branch** = output of `--abbrev-ref HEAD`.
- **Default branch**: detect with
  `git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'`.
  If that is empty, fall back to whichever of `master` / `main` exists
  (`git rev-parse --verify <name>`). If still ambiguous, ask the user.
- **Main checkout root** = the path on the FIRST `worktree ` line of
  `git worktree list --porcelain`.
- **In a linked worktree?** True when the current `--show-toplevel` differs
  from the main checkout root.

If the current branch already IS the default branch, there is nothing to merge: report and stop.

## 2. Commit pending changes

If `git status --short` shows any changes (staged, unstaged, or untracked that belong in the repo):

1. Follow the repo's commit conventions (inspect `CLAUDE.md` and `git log --oneline -5` for style, prefixes, and whether an AI co-author trailer is wanted).
2. Propose the commit message to the user and get alignment before committing.
3. Write the message to `/tmp/claude-<epoch-ms>.md` with the Write tool and commit with `git commit -F <file>` (never heredocs / `echo` / `$()`).

If the working tree is clean, skip this step.

Do not commit files that look like secrets. If unsure whether an untracked file belongs in the repo, ask rather than guess.

## 3a. In a linked worktree — merge and clean up

Capture the worktree path and branch name while still inside it, then:

1. `cd` to the main checkout root.
2. Confirm it is on the default branch (`git rev-parse --abbrev-ref HEAD`). If it is on some other branch or has uncommitted changes, stop and report instead of switching or stashing.
3. Merge: `git merge --no-ff --no-edit <branch>`.
   - On conflict: stop, do not auto-resolve, report the conflicting files.
4. Remove the worktree: `git worktree remove <worktree-path>` (without `--force`; if it refuses due to leftover files, report instead of forcing).
5. Delete the branch locally: `git branch -d <branch>`. Do not touch any remote branch.
6. Show `git log --oneline -3` and `git worktree list`.

## 3b. Not in a worktree — just merge

1. Switch to the default branch: `git switch <default>`.
2. Merge the feature branch: `git merge --no-ff --no-edit <feature-branch>`.
   - On conflict: stop, do not auto-resolve, report.
3. Leave the feature branch in place and do not remove anything else. Show `git log --oneline -3`.

## 4. Report

State plainly:

- The merge commit created (hash + subject).
- Worktree removed and branch deleted, if applicable.
- That nothing was pushed — the default branch is now ahead of its remote locally — and offer to push if they want.

## Safety rules

- Never `git push`, `git reset --hard`, `git rebase`, `git commit --amend`, or `--no-verify`.
- Never `--force` a worktree removal or a branch delete (`-D`) without explicit user consent.
- Never resolve merge conflicts automatically; hand them back to the user.
- Never delete a remote branch.
