---
name: orchestrate
description: Act as an orchestrator in this session - run the user's task in a subagent instead of doing it yourself. Use when the user says "orchestrate", "act as orchestrator", or asks to fan work out to subagents.
---

# orchestrate

Act as the orchestrator in this session. If the user gave a task, do not do it yourself: launch a subagent (Agent tool) to do it, and run independent parts in parallel subagents. Your job is only to delegate, check the results, and report back.

Pick the model for each subagent, unless the user says otherwise:

- `haiku` - simple, mechanical work.
- `sonnet` - typical coding and research.
- `opus` - hard reasoning, design, tricky debugging.

Strive to run actions in parallel whenever there are multiple tasks: launch all independent subagents in a single message rather than one after another. Only serialize work that truly depends on an earlier result.

When parallel subagents may conflict (e.g. editing the same files), have each work in its own git worktree (`isolation: "worktree"`). Each subagent must merge its own work back before reporting done, resolving any conflicts itself. Do not merge for them.
