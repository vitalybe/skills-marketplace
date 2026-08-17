---
name: _internal-step-plan
description: Create and review an implementation plan for a development task. Use when requirements are gathered and it's time to plan, or when the user invokes /devflow:_internal-step-plan. Also trigger on phrases like "plan this", "let's plan", "write the implementation plan", "how should we build this". Includes sub-agent review and user approval. This is phase 2 of the dev task flow.
---

# Plan Creation & Review

User input goes through gates - see **Gates** in the common instructions
below.

## General

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/flow-common-start.md`
</common-instructions>

## Step: Locate the Plan File

Use the path injected in `<plan-path>` (see Environment details above).
Edit that file throughout this phase. The `## Requirements Brief` (top)
and full `## Requirements` (bottom) were written in phase 1 - you're
filling in `## Plan`, `## Tests`, and `## Acceptance` here.

## Step: Review Project Docs

Read architecture docs relevant to this task:

1. Read the architecture doc index in CLAUDE.md
2. Identify which specific docs are relevant based on the task description - read those docs
3. Also read the pattern docs referenced by the task's code areas

Do NOT skip this step or only read generic pattern docs. The architecture docs contain critical domain knowledge (data flows, caching strategies, API contracts) that prevents wasted exploration later.

## Step: Explore the Codebase

Use the Explore agent to understand the current state of relevant code.

## Step: Draft the Plan

The plan-format reference (authoritative) is:

<plan-format>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/plan-format.md`
</plan-format>

What goes inside `## Plan`, and how `## Tests` relates to it, is
specified above under **Plan format**. Follow it exactly; it is
authoritative. Don't improvise structure here.

When the plan file has a `## Design` section, the Main Changes **UI and UX
Flows** subsection references it and must match it - don't restate or
contradict the recorded design.

Read `${CLAUDE_PLUGIN_ROOT}/docs/plan-guidelines.md` and draft against
that rubric - it's what the plan review judges the draft by.

Once the initial draft is written, save and commit the plan file.

## Step: Review

**Resume:** if `## Plan Review Findings` already holds findings with no
decisions recorded against them, skip re-running the review - go straight to
presenting them and recording the outcomes.

### 1. Run the review

Invoke `/devflow:_internal-review-aggregator` with:

- **Artifact** - `plan`.
- **Scope** - the plan file path.
- **Context** - task requirements/goals and relevant context (parent task,
  referenced docs) so the reviewers can judge completeness.

It resolves the plan roster (see `${CLAUDE_PLUGIN_ROOT}/docs/review-roster.md`),
runs the lanes in parallel, and returns one triaged, source-tagged findings list
(Apply / Decision needed) plus any reviewer skip notes.

### 2. Apply the Apply tier

Edit the plan file for each **Apply** item. Don't apply edits you don't
understand - move those to Decision needed instead. Commit when all Apply edits
are in (a single commit is fine - the plan is one file).

### 3. Write the decision-needed findings into the plan

Record the **Decision needed** findings in the plan's `## Plan Review Findings`
section, then commit the plan file.

<report-format>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/review-report-format.md`
</report-format>

## Step: User Review

Present to the user (only after the plan file is saved):

- The plan file path as injected in `<plan-path>`.
- The report per the shared format above - Apply items as the brief
  one-line-each mention, then the **Decision needed** items as the severity
  breakdown, plus any reviewer skip notes.

Ask the user to approve the plan, or to say what to do about each
Decision-needed finding, keyed by that finding's `Q<n>` id.

End the gate turn with that report as the package - it is presented as
written, so word it for the user. Writing the decision-needed findings into
`## Plan Review Findings` in the step above is this gate's flush; no further
state needs saving before the turn ends.

## Step: Record the Review Decisions

Once the answers are in, record each finding's outcome in the plan per the
**Recording review outcomes in the plan** procedure in the report format above:
implement the fixes the user asked for, note rejections with their reason and
questions with their answer, and move anything the user ignored to
`### Unhandled`. Commit the plan file. This phase does not complete until the
plan carries all of it.

## Wrap Up

1. Make sure the plan file reflects the final approved plan and the recorded review decisions (commit any pending edits).
2. Report completion: the plan file path and the commit.
