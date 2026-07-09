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
| _empty_ | `/devflow:_internal-step-requirements` |
| `Requirements` | `/devflow:_internal-step-plan` |
| `Plan` | `/devflow:_internal-step-code` |
| `Code` | `/devflow:_internal-step-close` |
| `Done` | task is closed - stop and consult the user |

Run the next skill. If the output of `flow-progress-get` doesn't match
any of the rows above (e.g. a typo or stale marker), stop and consult
the user.
