---
name: start-flow
description: Runs the devflow workflow end to end - works out which phases the task needs, runs each phase in its own sub-agent, and relays their questions to the user. Invoke to start or resume a dev task flow.
---

# Dev Task Orchestrator

Thin orchestrator: decide nothing about the work itself. Work out which
phases still need to run, run each in its own sub-agent, and carry messages
between those sub-agents and the user.

## Preflight

<dependencies>
!`${CLAUDE_PLUGIN_ROOT}/bin/doctor`
</dependencies>

Any `MISS` → stop and tell the user what to install (use the hint shown)
before starting - the phases call these tools and will fail without them.
Exception: in task-less mode a `MISS` on `jira` / the JIRA token is harmless
(those tools are never called) - proceed.

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/flow-common-start.md`
</common-instructions>

## Orchestrator markers

<orchestrator-run>
!`${CLAUDE_PLUGIN_ROOT}/../../aie-orchestrator-skills/*/bin/orchestrator-env 2>/dev/null || echo "detection-unavailable"`
</orchestrator-run>

- **`no`** (ordinary session): skip every step below that invokes an
  `aie-orchestrator-skills:` skill, step 5 included, as if unwritten -
  nothing pauses before close. Everything else runs unchanged, the final
  completion report included.
- **`yes`**: those steps are part of the flow. Emit every marker yourself, at
  top level - one emitted inside a sub-agent never reaches the backend.
- **`detection-unavailable`**: `aie-orchestrator-skills` is not installed, so
  there is nothing to emit markers to. Treat as `no`, and say so once:
  *orchestrator detection unavailable - running without markers.*

## Procedure

1. **Map the phases.** Spawn `/devflow:_internal-step-phase-mapping` in a
   sub-agent (model: opus), passing the user's request verbatim. It returns
   the flow, a `why` line, and one `phase:` line per phase still to run -
   name, skill, model. The mapping owns all of that: use its phases, skills
   and models exactly as returned, never your own. `phases: none` → report
   that to the user and stop.

2. **Record tasks.** One Claude Code task per returned phase, in order. Mark
   a task complete only when that phase's sub-agent reports the phase done.

3. **Run the phases**, one at a time, in the returned order. For each:
   1. Invoke `aie-orchestrator-skills:orchestrator-phase` with the phase
      name title-cased (`Requirements`, `Design`, `Plan`, `Code`, `Close`)
      and emit its marker before the sub-agent starts.
   2. Run the phase in its own sub-agent: the mapping's skill, on the
      mapping's model, with the spawn prompt below.
   3. While it needs input, relay its gates (see **Relaying gates**).
   4. On its completion report: mark that phase's task complete, then start
      the next phase. If it reports failure or blocked: stop, leave that
      phase's task incomplete, and report to the user.

4. **When `requirements` reports:** add or drop the `design` task per its
   `UX/UI:` line, placing it directly after `requirements`. Both flows can
   include design. Skill and model come from the mapping's `design` phase
   line when it scheduled one, otherwise from its `design-row:` line - never
   from a value you supply yourself.

5. **When `code` reports complete and `close` is still pending:** block the
   merge on a human. Invoke `aie-orchestrator-skills:orchestrator-gate` with
   email `vbelman@drivenets.com` and reason `devflow sign-off before close`,
   emit its marker, and **end the turn** - no close sub-agent, no further
   edits, nothing after the marker implying more work this turn. Not the
   code phase's own approval: that settles the implementation, this blocks
   the merge. When told it cleared, re-run this skill from the top; the
   mapping returns `close` as the only phase left. The fast path has no
   `close` and never gates here.

6. **When the last phase is done:** report what the phases produced (plan
   path, commits, PR url), orchestrated or not. Then, orchestrated only,
   invoke `aie-orchestrator-skills:orchestrator-flow-done` - only once every
   phase reported complete; if one failed or is blocked, report that and emit
   no done marker.

## Spawn prompt

Contains ONLY:

1. One line invoking the skill via the Skill tool, e.g. "Invoke the skill
   `devflow:_internal-step-requirements` and follow it."
2. The user's request, verbatim.
3. The phase-mapping's `why` line for this phase.
4. Session-specific facts the skill can't re-derive itself, if any (e.g.
   "ignore the unrelated uncommitted changes in X", a worktree path that
   differs from the default CWD).

Nothing else: the step skill re-injects branch, config, issue details, and
plan path itself when it loads, and carries its own sub-agent reporting
instructions.

## Relaying gates

Phase sub-agents cannot talk to the user. A phase needing input ends its
turn with a gate package - the report text plus questions with `Q<n>` ids
(see **Gates** in the common instructions). Then:

1. Relay the package **verbatim** - no summarizing, no additions, never an
   answer of your own. Print its prose sections (overview, applied fixes,
   plan path, skip notes) as your message first, then `AskUserQuestion` for
   the questions.
   - When the package points at review findings in the plan file: read that
     section (`### Unhandled`) and ask one question per open `Q<n>` -
     `question` carries the finding's body copied whole, so the user decides
     from the prompt itself; `options` carry its **Options.** choices
     (free-form when it lists none). Never shorten a finding to fit an
     option label. At most 4 questions per call, the rest in a follow-up
     call, never merged.
2. `SendMessage` the decisions back to the **same** sub-agent, keyed by Q-id.
3. Repeat until that sub-agent explicitly reports the phase complete.

Recovery rules:

- Sub-agent gone or degraded (interrupted session, long gap, no response):
  spawn a fresh one of the same phase skill - the normal spawn prompt plus a
  line telling it to resume from the plan file, with the user's decisions by
  Q-id. The phase skills re-enter from plan state.
- A turn ending with neither a gate package nor a completion report is an
  error: ask (`SendMessage`) instead of assuming either.
- A completion report naming findings as recorded but not decided is an
  unmet gate: `SendMessage` for them as a gate package.
