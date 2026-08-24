---
name: start-flow-worktree
description: Runs the devflow workflow in an isolated git worktree - sets up a dedicated worktree branch first, then starts the flow there. Use instead of /devflow:start-flow when the work should not touch the current checkout, when sitting on main/master, or on phrases like "start the flow in a worktree", "run this task on its own branch", "isolate this task and start the flow".
---

# Dev Task Orchestrator - worktree first

Same flow as `/devflow:start-flow`, preceded by worktree setup so nothing
accumulates on a shared branch.

Run both steps inline, in this order, in the same turn. Do not fork - step 1
changes the session's directory.

## Step 1: Get onto a worktree branch

Invoke the skill `devflow:use-worktree-branch` and follow it, passing the
user's request verbatim so it can name the branch from the task.

Stop there only if it stops: an unresolvable default branch, or a stash-pop
conflict. Report that and do not start the flow. If it reports the session is
already in a linked worktree, that is success - carry on.

Its final "carry on with the task" step is satisfied by step 2 below: do not
start implementing the work yourself.

## Step 2: Run the flow

In the worktree, invoke the skill `devflow:start-flow` and follow it, passing
the user's request verbatim. Everything from there - phase mapping, sub-agents,
gates - is that skill's job.
