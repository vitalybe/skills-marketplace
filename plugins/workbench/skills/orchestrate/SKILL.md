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

When parallel subagents may conflict (e.g. editing the same files), have each work in its own git worktree (`isolation: "worktree"`). Each subagent must merge its own work back before reporting done, resolving any conflicts itself. Do not merge for them.
