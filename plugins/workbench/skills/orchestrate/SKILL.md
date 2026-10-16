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
