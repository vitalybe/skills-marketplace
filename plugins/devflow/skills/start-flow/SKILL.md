---
name: start-flow
description: Runs the devflow workflow end to end - works out which phases the task needs, runs each phase in its own sub-agent, and relays their questions to the user. Invoke to start or resume a dev task flow.
---

# Dev Task Orchestrator

Thin orchestrator. It decides nothing about the work itself: it works out
which phases still need to run, runs each one in its own sub-agent, and
carries messages between those sub-agents and the user.

## Preflight: Dependencies

<dependencies>
!`${CLAUDE_PLUGIN_ROOT}/bin/doctor 2>&1 || true`
</dependencies>

If any dependency is reported `MISS`, stop and tell the user what to
install (using the hint shown) before starting the flow - the phases
call these tools and will fail without them.

Exception: in task-less mode a `MISS` on `jira` / the JIRA token is
harmless (those tools are never called) - proceed.

## General

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/flow-common-start.md`
</common-instructions>

## Step: Work out the phases

Spawn `/devflow:_internal-step-phase-mapping` in a sub-agent (model:
opus), passing the user's request verbatim. It inspects the plan file and
the request, and returns the chosen flow, one line of reasoning, and one
`phase:` line per phase still to run - each naming the phase, the skill
that runs it, and the model to run it on.

The mapping owns all of that: take the phases, skills and models exactly
as returned and do not substitute your own.

If it returns `phases: none`, report that to the user and stop.

## Step: Record the phases as tasks

Record each returned phase as a Claude Code task, in order. Mark a task
complete only when that phase's sub-agent reports the phase done.

## Step: Run each phase

Run the phases one at a time, in the returned order, each in its own
sub-agent: invoke the skill the mapping gave for that phase, on the model
the mapping gave for that phase. Pass it the user's request verbatim plus
the phase-mapping reasoning.

Mark the phase's task complete, then start the next phase's sub-agent. If
a phase reports failure or that it is blocked, stop, mark nothing
complete, and report to the user.

When the last phase is done, report what the phases produced (plan path,
commits, PR url).

### Relaying user interaction

Phase sub-agents cannot talk to the user. When a phase needs input -
requirements Q&A, a review decision, an approval gate - it ends its turn
and returns the questions or report to you. Then:

1. Relay it to the user **verbatim**: `AskUserQuestion` where the choice
   is closed (approve / needs changes, pick findings to apply), free-form
   otherwise. Never answer on the user's behalf and never summarize a
   question away.
2. Send the answers back to the **same** sub-agent with `SendMessage`, so
   it continues where it left off - do not spawn a fresh one.
3. Repeat until that sub-agent explicitly reports the phase complete.

A phase is done only when its sub-agent says it is done. If a sub-agent
ends its turn with neither questions nor a completion report, ask it
(`SendMessage`) instead of assuming either.
