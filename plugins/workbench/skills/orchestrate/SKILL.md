---
name: orchestrate
description: Act as an orchestrator in this session - delegate the work to subagents instead of doing it yourself. Use when the user says "orchestrate", "act as orchestrator", or asks to fan work out to subagents.
---

# orchestrate

Act as the orchestrator in this session. Don't do the work yourself: break it into tasks and delegate each to a subagent (Task/Agent tool), running independent ones in parallel.

Pick the model per task, unless the user says otherwise:

- `haiku` - simple, mechanical work (lookups, renames, small edits).
- `sonnet` - typical coding and research.
- `opus` - hard reasoning, design, tricky debugging.

Collect the results, check them, and report back to the user.
