---
name: start-flow-orchestrator
description: The devflow flow with this SDLC's orchestrator phase and gate rules layered on - emits the step markers, blocks the merge on a human sign-off gate, and closes the run. Invoke instead of /devflow:start-flow when the flow runs as a step in an orchestrator workflow, or on phrases like "run the flow under the orchestrator", "start the flow with markers".
---

# Dev Task Orchestrator - orchestrated run

Same flow as `/devflow:start-flow`, plus the markers and the gate that an
orchestrated run needs. The core flow knows nothing about any of this; every
orchestrator-specific rule lives in this file.

Run inline, in this turn. Do not fork: markers only reach the backend from the
top-level turn, and a sub-agent's never do.

## Step 1: Confirm the environment

<orchestrator-run>
!`${CLAUDE_PLUGIN_ROOT}/../../aie-orchestrator-skills/*/bin/orchestrator-env 2>/dev/null || echo "detection-unavailable"`
</orchestrator-run>

- **`yes`**: an orchestrated run. Continue with step 2.
- **`no`**: nobody is reading the markers and nothing can clear a gate, so
  emitting them would stop the flow at a gate that never lifts. Say so once -
  *not an orchestrated session: running the plain flow, no markers, no
  sign-off gate* - then invoke the skill `devflow:start-flow`, follow it, and
  ignore the rest of this file.
- **`detection-unavailable`**: `aie-orchestrator-skills` is not installed, so
  there is nothing to emit markers to. Say *orchestrator detection unavailable
  - running without markers*, then do exactly what **`no`** does.

## Step 2: Run the flow with markers

Invoke the skill `devflow:start-flow` and follow it, passing the user's request
verbatim. Its procedure is unchanged - phase mapping, one sub-agent per phase,
gate relaying. These rules apply while you follow it:

1. **Before each phase's sub-agent starts**, invoke
   `aie-orchestrator-skills:orchestrator-phase` with that phase's name
   title-cased (`Requirements`, `Design`, `Plan`, `Code`, `Close`) and emit its
   marker.
2. **When the `code` phase reports complete and `close` is still pending**,
   stop there and go to step 3 instead of starting `close`.
3. **When the last phase is done**, the core flow's own completion report is
   still what you present. Then go to step 4.

## Step 3: The sign-off gate

Block the merge on a human. Invoke `aie-orchestrator-skills:orchestrator-gate`
with email `rchocron@drivenets.com` and reason `devflow sign-off before close`,
emit its marker, and **end the turn** - no close sub-agent, no further edits,
nothing after the marker implying more work this turn.

This is not the code phase's own approval: that settles the implementation,
this blocks the merge. When told the gate cleared, re-run this skill from the
top; the mapping returns `close` as the only phase left.

The fast path has no `close` phase and never reaches this step.

## Step 4: Close the run

Once the core flow has reported what the phases produced - plan path, commits,
PR url - invoke `aie-orchestrator-skills:orchestrator-flow-done` and emit its
marker.

Only when every phase reported complete. If one failed or is blocked, report
that and emit no done marker.
