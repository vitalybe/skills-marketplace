---
name: session-finalize
description: Finalize the work on a branch or worktree built in an interactive session (no devflow plan) - validate, review, update docs, and commit it properly. Targets the branch or worktree the user names, else the current one. Use after ad-hoc or exploratory coding with the user, or when the user says "finalize this session", "wrap up what we did", "review and document this", "clean this up before I push". Not for flow tasks - those finish in the close phase.
allowed-tools: Bash(/*/skills/_devflow-shared/bin/mdexec *)
---

# Session Finalize

Turn the unreviewed work of an interactive session - committed on the branch,
uncommitted, or both - into reviewed, documented, committed changes. It reuses the flow's own pieces;
there is no plan file and no task tracker.

## Phase 1: Scope

1. **Pick the target.** Use the branch or worktree the user named (skill arguments or
   message); otherwise the current checkout. Resolve a name with `git worktree list`.
   If the target is another worktree, enter it (`EnterWorktree` with its path) so every
   later phase runs there. A branch checked out nowhere: ask before creating a worktree
   for it.
2. **See what it holds.** Run `git status --short`, then
   `git log --oneline origin/main..HEAD` (fall back to `main`) and
   `git diff --stat $(git merge-base origin/main HEAD)` for the committed plus
   uncommitted total. The scope is everything the branch has over `main`, not just
   the working tree.
3. If the target is `main`/`master` itself, run `/devflow:use-worktree-branch` first so
   the work moves to its own branch.
4. Summarise the change in 2-3 lines and note anything that does not belong (debug code,
   scratch files, secrets). Ask before dropping or ignoring any of it.

## Phase 2: Rebase

Bring the branch onto current `main` so validation and review run against what will
actually merge:

1. `git fetch origin main`, then `git rebase --autostash origin/main`. Already up to
   date means nothing to do.
2. On conflicts, resolve the obvious ones and show the user what you chose; stop and
   ask on anything semantic. Never `--skip` a commit or abort silently. If the user
   declines the rebase, say so and carry on against the old base.
3. If the branch was already pushed, the rebase makes the next push a force push.
   Say so in the hand-off; use `--force-with-lease` only when the user agrees.

## Phase 3: Validate

Run the project's full validation:

<validation-procedure>
!`${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/bin/mdexec docs/validation-procedure.md --fallback ${CLAUDE_PLUGIN_ROOT}/skills/_devflow-shared/docs/validation-procedure.md || /home/agent/.cursor/skills/_devflow-shared/bin/mdexec docs/validation-procedure.md --fallback /home/agent/.cursor/skills/_devflow-shared/docs/validation-procedure.md`
</validation-procedure>

Fix failures and re-run until green. A failure outside this session's changes is
reported, not fixed.

## Phase 4: Review

Run `/devflow:code-review`. It applies the obvious fixes as separate commits and
reports the rest. Show the user the **Decision needed** findings and resolve the
ones they pick.

## Phase 5: Docs

Decide from the diff whether anything durable changed: behaviour, commands,
conventions, architecture, or a README/CLAUDE.md that now lies. If so, run
`/devflow:docs-update` for it; if not, say so in one line and skip. Do not
document the session itself.

## Phase 6: Commit

Group any uncommitted changes (and review fixes) into logical commits in the repo's style
(`git log -5 --oneline`). Stage by file, never `git add -A`. Do not push.

## Phase 7: Hand-off

Report: what was built, rebase result, validation result, findings fixed vs left open, docs touched,
commits made. Then offer the next step (push and open a PR, or the local merge via
`/devflow:_internal-step-close`'s merge route) and wait. Never push or merge unasked.
