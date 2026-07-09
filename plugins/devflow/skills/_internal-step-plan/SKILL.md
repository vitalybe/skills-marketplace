---
name: _internal-step-plan
description: Create and review an implementation plan for a development task. Use when requirements are gathered and it's time to plan, or when the user invokes /devflow:_internal-step-plan. Also trigger on phrases like "plan this", "let's plan", "write the implementation plan", "how should we build this". Includes sub-agent review and user approval. This is phase 2 of the dev task flow.
---

# Plan Creation & Review

## General

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/flow-common-start.md`
</common-instructions>

## Start

- `${CLAUDE_PLUGIN_ROOT}/bin/tasks flow-progress-set <KEY> Plan`

## Step: Locate the Plan File

Use the path injected in `<plan-path>` (see Environment details above).
Edit that file throughout this phase. The `## Requirements Brief` (top)
and full `## Requirements` (bottom) were written in phase 1 - you're
filling in `## Plan`, `## Tests`, and `## Acceptance` here.

## Step: Review Project Docs

Read architecture docs relevant to this task:

1. Read the architecture doc index in CLAUDE.md (under "Architecture Documentation")
2. Identify which specific docs are relevant based on the task description - read those docs
3. Also read the pattern docs referenced by the task's code areas

Do NOT skip this step or only read generic pattern docs. The architecture docs contain critical domain knowledge (data flows, caching strategies, API contracts) that prevents wasted exploration later.

## Step: Explore the Codebase

Use the code-explorer agent to understand the current state of relevant code.

## Step: Draft the Plan

The plan-format reference (authoritative) is:

<plan-format>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/plan-formats.md`
</plan-format>

What goes inside `## Plan`, and how `## Tests` relates to it, is
specified above under **Plan format**. Follow it exactly; it is
authoritative. Don't improvise structure here.

Once the initial draft is written, save and commit the plan file.

## Step: Sub-agent Review

Launch a general-purpose sub-agent (model=opus) with:

- The plan file path (so it can read `$path` directly)
- Task requirements/goals
- Relevant context (parent task, referenced docs)

The agent should evaluate:

- **Completeness**: All requirements covered?
- **Correctness**: Interfaces and data flows make sense?
- **Consistency**: Aligns with codebase patterns?
- **Test coverage**: Testing strategy present? Every concern group carries a `Tests:` sub-bullet? Rollup matches the inline cases?
- **Risk areas**: Edge cases, race conditions, failure modes?
- **Over-engineering**: Anything unnecessary?
- **Dependencies**: Hidden ordering issues?

Triage each finding into one of:

- **Apply** — clear gap or correction with an unambiguous edit to the plan.
- **Decision needed** — false positive, out of scope, stylistic, or a judgment call the user should make.

Don't apply edits you don't understand. When in doubt, leave it for the user to decide and surface it.

For each "Apply" item, edit the plan file. Save and commit when all "Apply" edits are in (single commit is fine — the plan is one file).

Then `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Sub-agent plan review completed"`.

### Report to the user

Render the findings as the Apply / Decision needed triage from the report format:

<report-format>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/review-report-format.md`
</report-format>

## Step: User Review

Present the plan to the user (only after the plan file is saved and both outputs above are emitted):

- Path to the plan file: `_plans/<KEY>-*.md`
- Reference to the two outputs above (don't restate them — they're already in the transcript).

Request the user to approve the plan, or pick from the Decision needed list what to apply.

If changes are requested:

- Update the plan file.
- Commit the plan file.
- `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Plan updated after user review: <reason>"`

## Wrap Up

1. Make sure the plan file reflects the final approved plan (commit any pending edits).
2. `${CLAUDE_PLUGIN_ROOT}/bin/tasks flow-progress-set <KEY> Code`
3. `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Plan creation complete - user approved"`
4. Run the `/devflow:start-flow` skill to find the next phase.
