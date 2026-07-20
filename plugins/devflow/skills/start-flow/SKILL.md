---
name: start-flow
description: Invoke to find the next phase in the devflow workflow.
---

# Dev Task Orchestrator

Runs all devflow phases in sequence by launching each one.

## Preflight: Dependencies

<dependencies>
!`${CLAUDE_PLUGIN_ROOT}/bin/doctor 2>&1 || true`
</dependencies>

If any dependency is reported `MISS`, stop and tell the user what to
install (using the hint shown) before starting the flow - the phases
call these tools and will fail without them.

## General

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/flow-common-start.md`
</common-instructions>

## Phase Sequence

The phases are:

- `/devflow:_internal-step-requirements` - Gather requirements for a development task.
- `/devflow:_internal-step-plan` - Create and review an implementation plan.
- `/devflow:_internal-step-code` - Implement the plan, run tests, and review code.
- `/devflow:_internal-step-close` - Close the task by running validation and merging.

## Step: Read Current Phase

<current-phase>
!`${CLAUDE_PLUGIN_ROOT}/bin/tasks flow-progress-get`
</current-phase>

Map the phase to the next skill:

| `<current-phase>` | Next skill |
|---|---|
| _empty_ | **Triage first** (see below); take the fast path, or start `/devflow:_internal-step-requirements` |
| `Requirements` | `/devflow:_internal-step-plan` |
| `Plan` | `/devflow:_internal-step-code` |
| `Code` | `/devflow:_internal-step-close` |
| `Done` | task is closed - stop and consult the user |

Run the next skill. If the output of `flow-progress-get` doesn't match
any of the rows above (e.g. a typo or stale marker), stop and consult
the user.

## Step: Triage the task (fresh flow only)

Run this **once**, only when `<current-phase>` above is empty (a brand-new
task). On any later re-entry (a phase is already set), skip triage entirely and
use the phase map.

Assess the task's scope:

- **Fast path** - the change is small and self-contained, with no meaningful
  design decision and no cross-cutting risk: a UI-only tweak, a single script, a
  skill/doc edit, a localized bug fix, a copy change.
- **Full flow** - anything larger or feature-shaped: several files, a new
  component with tests, a product/design/security decision, or a cross-cutting or
  risky change.
- **When unsure, choose the full flow.**

**Override.** If the invoker explicitly asked for a route - "fast path" /
"simple", or "full flow" / "run all the phases" - honor that and skip the
assessment.

**If fast path:** implement the change directly (match existing style), run the
project's checks/tests, and commit per the flow's commit conventions - do NOT
walk the four phases or run the formal review gate. Then stop and report. Leave
integration (PR / merge) to the same policy the close phase would apply; do not
merge or open a PR on your own initiative.

**If full flow:** proceed to `/devflow:_internal-step-requirements` and continue
through the phase map as normal.
