---
name: _internal-step-phase-mapping
description: Triage a dev task and return the devflow phases still to run. Invoked by /devflow:start-flow in a sub-agent - not invoked directly by the user.
---

# Phase Mapping

Work out which flow the task takes and which of its phases are still
outstanding, then return that to the orchestrator. Do not run a phase,
edit code, or touch the plan file.

Inputs: the environment details below plus the user's request as passed by
the orchestrator.

## General

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/flow-common-start.md`
</common-instructions>

## The phases

The canonical phase definitions - the phase name, the skill that runs it,
and the model it runs on:

| Phase          | Skill                                  | Model  |
| -------------- | -------------------------------------- | ------ |
| `requirements` | `/devflow:_internal-step-requirements` | opus   |
| `plan`         | `/devflow:_internal-step-plan`          | opus   |
| `code`         | `/devflow:_internal-step-code`          | opus   |
| `close`        | `/devflow:_internal-step-close`         | sonnet |

(This phase-to-model mapping may change.)

Which phases each flow includes, in run order:

- **fast**: `requirements`, `code`
- **full**: `requirements`, `plan`, `code`, `close`

## Step: Pick the flow

Assess the scope of the work:

- **Fast path** - small and self-contained, no meaningful design decision
  and no cross-cutting risk: a UI-only tweak, a single script, a skill/doc
  edit, a localized bug fix, a copy change. Requirements may be a quick
  confirmation; the plan phase is skipped entirely.
- **Full flow** - anything larger or feature-shaped: several files, a new
  component with tests, a product/design/security decision, or a
  cross-cutting or risky change.
- **When unsure, choose the full flow.**

**Override.** If the request explicitly asks for a route - "fast path" /
"simple", or "full flow" / "run all the phases" - honor it and skip the
assessment.

## Step: Detect what's already done

There is no stored phase marker: infer progress from the plan file at
`<plan-path>` and the branch's commits. Read the plan file if it exists.

- no plan file, or `## Requirements` empty → requirements pending
- `## Plan` empty → plan pending
- `## Plan Review Findings` populated → the plan phase finished
- commits on the branch beyond the plan file → code underway
- `## Code Review Findings` populated → code review done, only close left
- branch already merged, or a PR already open → nothing left to run

Drop the completed phases off the front of the flow's list and keep the
rest in flow order. When the signals are ambiguous, treat the earliest
ambiguous phase as pending - re-running a phase is cheap, skipping one is
not.

## Return

Return exactly this to the orchestrator, nothing else:

```
flow: fast | full
why: <one line - what you inferred and why this flow>
phase: <name> <skill> (<model>)
phase: <name> <skill> (<model>)
```

One `phase:` line per remaining phase, in run order, with the skill and
model taken verbatim from the phase table. If nothing is left to run, emit
`phases: none` in place of the `phase:` lines.

Example:

```
flow: full
why: plan file has requirements only, so plan onward is pending
phase: plan /devflow:_internal-step-plan (opus)
phase: code /devflow:_internal-step-code (opus)
phase: close /devflow:_internal-step-close (sonnet)
```
