---
name: orchestrator-drive
description: Take over and drive a specific orchestration task's in-pane gates to completion, on the user's explicit request. Use inside a herdr orchestration session (see `/workbench:orchestrator-init`) when the user names one or more tracked tasks and tells you to push them through - phrases like "drive it to completion", "drive Dev-connect and Composer", "push the composer task through", "answer its gates and keep it moving". This is the deliberate exception to the standing "don't proxy in-pane gates" rule, scoped to exactly the named task(s). If the user has not explicitly asked you to drive a named task, do NOT use this skill - leave gates for the user to answer in the pane.
---

# orchestrator-drive - drive a task's gates to completion

By default an orchestrator is hands-off: it watches tracked task tabs and
summarizes them in the status doc, but never answers their in-pane gates - those
are the user's to answer in the pane (see `/workbench:orchestrator-init` §3). This
skill is the **explicit-request exception**: the user names a task (or a few) and
tells you to drive it through. You then answer that task's gates yourself and push
it to a committed state.

## Prerequisites

- `HERDR_ENV=1` and you are the orchestrator of a running session (you have a
  status-doc target and tracked child tabs). If not, this skill does not apply.
- The user **explicitly named the task(s)** to drive. Never infer a drive
  authorization - "drive it to completion", "push Composer through", "keep New
  Task UI moving" all qualify; ambient impatience does not. If it is unclear
  which task, ask which before driving anything.

## Scope - only the named task(s)

Drive **exactly** the task(s) the user named, and nothing else. Every other
task's gates stay hands-off. Do not start answering gates in tabs that were not
part of the instruction, even if they are sitting blocked. If the user says
"drive everything", that covers the currently active tasks - still not future
spawns unless they say so.

## Driving loop, per named task

1. **Mark it as driven - in the tab AND the doc.** So it is visible both in the
   tab bar and in the status doc:
   - **Tab:** insert 🚗 into the tab label, after the `T<n> - ` prefix:
     `T4 - New Task UI` -> `T4 - 🚗 New Task UI`. Look up the tab id from the spawn
     registry and rename it:
     ```bash
     herdr tab rename <tab_id> "T<n> - 🚗 <Name>"
     ```
   - **Doc:** prefix the task's line with 🚗 (instead of 🟡) and say so in the
     status text, per [orchestrator-init's status-doc-format](../orchestrator-init/references/status-doc-format.md),
     e.g. `- [ ] 🚗 **New Task UI** - auto-driving; awaiting plan approval`.

   This is how the user sees, at a glance in both places, which tasks you are
   steering versus which they still own.

2. **Read the pane right before acting.** `herdr pane read <pane> --source recent`.
   Confirm it is actually parked at a gate and read the exact question. A tab in
   auto mode may have cleared the gate already - if it is working again, do not
   send anything; just update the doc.

3. **Answer the gate.** Approve the plan / answer the requirement so the task
   advances (typically into the Code phase). Send input through task-herdr's I/O
   helper - a gate-blocked agent reports `blocked` and never goes idle, so the
   plain idle-guarded `send` refuses; use `--force`:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/task-herdr/scripts/herdr-io.sh send <pane> --file <answer-file> --force
   ```

   (or read the pane and send the exact keystroke). Write multiline answers to a
   temp file and pass `--file`.

4. **Judgment calls: follow the agent's own lean.** When a gate asks you to pick
   between reasonable options (a token name, a small UX detail), go with the
   reviewer's or the agent's stated recommendation unless the user gave a
   direction. Do not invent scope or make product decisions that are genuinely the
   user's - if a gate needs a real product/security call the user has not
   delegated, stop driving that one and surface it.

5. **Verify it advanced**, then update the doc line to the new real state (still
   🚗 while you keep driving). Keep answering successive gates until the task
   reaches a committed, code-complete state.

## Stop at integration - unless told otherwise

Driving authorizes answering gates and reaching a **committed** state. It does
**not** authorize integration. When the driven task genuinely commits (pane says
code phase complete/committed AND the branch has real implementation commits),
drop the 🚗 marker from **both** the tab label (`herdr tab rename <tab_id>
"T<n> - <Name>"`) and the doc line, set the line to **ready to integrate**, and
**wait for explicit confirmation** before merging - exactly the standing rule in
`/workbench:orchestrator-init` §3.

The one exception: if the drive instruction itself included integration - e.g.
"drive it to completion, **merge and close**" - then that is your confirmation to
integrate that task once it is genuinely done (verify first, then merge via the
session's integration path; close the tab only if the user's standing rule allows
it).

## Common mistakes

- **Driving a tab the user did not name.** The authorization is per-task. A
  different blocked tab is still the user's to answer.
- **Using plain `send` on a gate.** A gate-blocked agent never goes idle, so the
  idle-guarded `send` times out and refuses. Use `--force`, or send the exact
  keystroke after reading the pane.
- **Not re-reading the pane before sending.** An auto-mode tab may have moved past
  the gate; sending then types over a now-working agent. Re-read immediately
  before each send.
- **Merging because you were told to "drive".** Driving stops at a committed
  state. Merge/close needs its own explicit confirmation unless the drive
  instruction said so.
- **Forgetting the 🚗 marker.** The user relies on it to tell which tasks are
  hands-off (theirs) versus auto-driven (yours). Mark **both** the tab label and
  the doc line on start; unmark both on stop.
