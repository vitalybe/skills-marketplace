---
name: _internal-step-requirements
description: Gather requirements for a development task. Use when starting a new dev task, when requirements are unclear, or when the user invokes /devflow:_internal-step-requirements. Also trigger on phrases like "new task", "start a feature", "let's build X", "I want to add Y" - even without the slash command. Works with or without a task-tracker key. This is phase 1 of the dev task flow.
---

# Requirements Gathering

User input goes through gates - see **Gates** in the common instructions
below.

## General

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/flow-common-start.md`
</common-instructions>

## Gather Requirements

Ask clarifying questions to understand:

- Core use cases and user flows
- Data structures and relationships
- UI/UX requirements
- Edge cases and special behaviors
- Integration points with existing features

For sub-tasks of a parent issue:

- Focus only on what's specific to this task
- If anything conflicts with the parent, confirm with the user

**Key principle**: Don't assume - ask when unclear. Present all questions together in one organized list. Continue until all are answered.

Give each question a stable `Q<n>` id and keep the ids across rounds. As each
round of answers lands, write it into the plan file's `## Requirements`
(creating the file per **Step: Write the Plan File** below if it isn't there
yet) and save - so a respawned agent picks the interview up from the plan.
Commit at wrap-up.

## Step: Write the Plan File

Use the path injected in `<plan-path>` (see Environment details above).
The plan-format reference (authoritative for the file shape) is:

<plan-format>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/plan-format.md`
</plan-format>

1. If the file doesn't exist yet, create it with the scaffold shown
   under **Structure** above (the H1 plus its headings). Don't improvise
   headings here.
2. Fill in the full `## Requirements` section (bottom of the file) from
   the Q&A you just did.
3. Distill it into `## Requirements Brief` at the top: 1-2 sentences on
   what we want and why. The brief orients the reader; the full section
   is reference.

## Wrap Up

1. Save the plan file edits.
2. Commit the plan file.
3. Report completion: the plan file path, the commit, and one line on
   whether UX/UI changes are in scope - `UX/UI: yes - <what changes>` or
   `UX/UI: no`. The orchestrator adds or drops the design phase from it.
