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

## Orchestrator markers

<orchestrator-run>
!`[ -n "${ORCHESTRATOR_ENVIRONMENT:-}" ] && echo yes || echo no`
</orchestrator-run>

`no` means this is an ordinary session: emit no marker anywhere in this
skill, skip every step below that calls an `aie-orchestrator-skills:` skill,
and run the flow exactly as if those steps were not written. `yes` means the
run is orchestrated and the markers below are part of the flow.

Every marker is yours to emit, never a phase sub-agent's - a marker emitted
inside a sub-agent never reaches the orchestrator backend.

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

Run the phases one at a time, in the returned order. For each phase:

1. Invoke `aie-orchestrator-skills:orchestrator-phase` with that phase's name
   title-cased, e.g., `Requirements`, `Design`, `Plan`, `Code`, `Close` - and emit
   its marker before the sub-agent starts.
2. Run the phase in its own sub-agent: invoke the skill the mapping gave for
   that phase, on the model the mapping gave for that phase. Pass it the spawn
   prompt below.

**Design task.** When the requirements phase reports, add or drop the
`design` task per its `UX/UI:` line, keeping it ahead of `plan`. It runs
`/devflow:_internal-step-design` on opus - take the skill and model from the
mapping's table when it returned a `design` line.

### Spawn prompt

Contains ONLY:

1. One line invoking the skill via the Skill tool, e.g. "Invoke the skill
   `devflow:_internal-step-requirements` and follow it."
2. The user's request, verbatim.
3. The phase-mapping's `why` line for this phase.
4. Session-specific facts the skill can't re-derive itself, if any (e.g.
   "ignore the unrelated uncommitted changes in X", a worktree path to use
   if it differs from the default CWD).

Nothing else: the step skill re-injects branch, config, issue details, and
plan path itself when it loads, and carries its own sub-agent reporting
instructions.

Mark the phase's task complete, then start the next phase's sub-agent. If
a phase reports failure or that it is blocked, stop, mark nothing
complete, and report to the user.

**Gate before close.** When the phase that just reported complete is `code`
and `close` is still to run, the run stops for a human sign-off before
anything merges. Invoke `aie-orchestrator-skills:orchestrator-gate` with
email `vbelman@drivenets.com` and reason `devflow sign-off before close`,
emit its marker, and **end the turn there** - do not start the close
sub-agent, make no further edits, and say nothing after the marker that
implies more work in this turn.

The code phase's own user approval is not this gate: that one settles the
implementation, this one blocks the merge on a named human. When the gate
clears you are told so; re-run this skill from the top, and the phase
mapping returns `close` as the only phase left. The fast path has no
`close` phase and so never gates here.

**Finishing the run.** When the last phase is done, report what the phases
produced (plan path, commits, PR url). That report happens either way.

Then, on an orchestrated run only, invoke
`aie-orchestrator-skills:orchestrator-flow-done` and emit `MARKER-DONE` as
the final line of that same message. Only once every phase has reported
complete - if one failed or is blocked, report that and emit no done marker.

### Relaying gates

Phase sub-agents cannot talk to the user. A phase needing input ends its
turn with a gate package - the report text plus questions with `Q<n>` ids
(see **Gates** in the common instructions). Then:

1. Relay the package **verbatim**: no summarizing, no additions, never an
   answer of your own. Print its prose sections (overview, applied fixes,
   plan path, skip notes) as your message **first**, then `AskUserQuestion`
   for the questions.

   When the package points at review findings in the plan file, read that
   section (`### Unhandled`) and ask one question per open `Q<n>`: `question`
   carries that finding's body from the plan, copied whole, so the user decides
   from the prompt itself; `options` carry its **Options.** choices (free-form
   when it lists none). Never shorten a finding to fit an option label. At most
   4 questions per call - findings past that go in a follow-up call, never
   merged.
2. `SendMessage` the decisions back to the **same** sub-agent, keyed by
   Q-id.
3. Repeat until that sub-agent explicitly reports the phase complete.

If the sub-agent is gone or degraded - interrupted session, long gap, no
response - spawn a fresh sub-agent of the same phase skill: the normal
spawn prompt plus one line telling it to resume from the plan file, with
the user's decisions listed by Q-id. The phase skills re-enter from plan
state.

A sub-agent ending its turn with neither a gate package nor a completion
report is an error: ask it (`SendMessage`) instead of assuming either.

A completion report that names findings as recorded but not decided is an
unmet gate, not a completion: SendMessage the sub-agent to return them as a
gate package.
