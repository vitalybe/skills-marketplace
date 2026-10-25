---
name: orchestrate
description: Act as an orchestrator in this session - run the user's task in a subagent instead of doing it yourself. Use when the user says "orchestrate", "act as orchestrator", or asks to fan work out to subagents.
---

# orchestrate

Act as the orchestrator in this session. If the user gave a task, do not do it yourself: launch a subagent (Agent tool) to do it, and run independent parts in parallel subagents. Your job is only to delegate, check the results, and report back.

Pick the model for each subagent, unless the user says otherwise:

- `sonnet` - the default for most tasks: coding, building, research, UI, tests, docs.
- `haiku` (Haiku 5.5) - exploration, searches, and data extraction.
- `opus` - reviews (code, plan, or result review), or as an advisor on a hard decision. Not for building.

Split a large job into several smaller subagents rather than one big brief on a single heavy model. Give each a narrow scope, run independent parts in parallel, and keep the heavy model for the small slice that needs it.

Subagents only get the instructions you pass them. If a subagent may spawn its own subagents for a complex task, put this same model rule in its brief: haiku for exploration, opus for review or advice, sonnet for everything else, and split the work the same way.

Strive to run actions in parallel whenever there are multiple tasks: launch all independent subagents in a single message rather than one after another. Only serialize work that truly depends on an earlier result.

When parallel subagents may conflict (e.g. editing the same files), have each work in its own git worktree (`isolation: "worktree"`).

Landing rule - include it in every worker brief:

- Target branch: work is always merged into the orchestrator's own branch, never assumed to be main or the default branch. At the start the orchestrator records it with `git branch --show-current` and tells every worker in the brief ("land into branch <name>"). If the orchestrator is on the default branch, that is the target.
- Workers never merge by hand. Each worker creates its worktree branch from the target branch, works in that worktree, commits, and as its last step lands the work by running the repo's land script if one exists (for example `scripts/land --into <branch> --message-file <file>`, where the message file is written with the Write tool and ends with the required Co-Authored-By line). The script merges the target branch in first, runs the fast tests, merges --no-ff into the target branch, and removes the worktree and branch only after success. It never pushes and stops on conflicts or test failures.
- The agent harness locks a worker's worktree while the worker is alive, so a worker cannot remove its own worktree. A land script that merges successfully but reports the worktree as locked has still landed the work: the worker reports the merge commit as done. After the hand-back the orchestrator removes the leftover worktree and branch as part of verification (`git worktree unlock <path>` if still locked, `git worktree remove <path>`, `git branch -d <branch>`, only when the branch is merged into the target), or has the landing subagent do it.
- If the repo has no land script, the worker merges its own branch --no-ff into the target branch itself, resolving conflicts, and removes the worktree.
- If a worker's sandbox blocks landing (git commands against the main checkout are refused), it commits on its branch, does not work around the block, and reports the branch name. The orchestrator then starts one small landing subagent (`sonnet`) whose only job is to run the same land script (with `--into <branch>`) or the --no-ff merge into that same target branch, run the tests, clean up, and report. The orchestrator itself does not run merges or edit code. If the landing agent is also blocked, report the branch and the exact commands to the user.
- After a hand-back, verify the result before reporting: `git log <branch>` shows the merge commit on the target branch, `git worktree list` has no leftover worktree for it, and no leftover processes remain.
