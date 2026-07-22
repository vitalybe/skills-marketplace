---
name: _internal-step-code
description: Implement the plan for a development task, run tests, and do a code review. Use when the plan is approved and it's time to write code, or when the user invokes /devflow:_internal-step-code. Also trigger on phrases like "implement this", "start coding", "build it", "write the code". Includes sub-agent code review and user approval. This is phase 3 of the dev task flow.
---

# Implementation & Code Review

## General

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/flow-common-start.md`
</common-instructions>

## Start

- `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Starting implementation"`
- `${CLAUDE_PLUGIN_ROOT}/bin/tasks flow-progress-set <KEY> Code`

## Step: Read the Plan

Read the full plan from the path injected in `<plan-path>` (see
Environment details above). If implementation reveals the plan needs
adjustment, edit that file (not the issue description), re-confirm
with the user, then commit the plan file.

## Step: Implement

- Follow the implementation plan step by step
- Prefer editing existing files over creating new ones
- Follow the developer guidelines defined below
- Git commit when implementation is complete (before moving to tests)

<developer-guidelines>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/developer-guidelines.md`
</developer-guidelines>

## Step: Run Tests

- Collect the test list from the plan: the `## Tests` rollup, following
  each line back to the `Tests:` sub-bullet in its concern group for
  the case-level detail.
- Run them; fix any failures.
- Add tests discovered during implementation - record each in its
  concern group's `Tests:` sub-bullet and in the rollup, then commit
  the plan file alongside the test code.

## Step: Update Documentation

Review what changed in this task:

- New features or functionality
- Modified behavior or interfaces
- New patterns or conventions
- Architecture or data flow changes

Run `/devflow:docs-update` with the list of changes to guide the documentation update.

- Git commit the documentation changes.
- `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Documentation update complete"`

## Step: Code Review

Run the review roster via the aggregator, then apply and report.

### 1. Run the review

Invoke `/devflow:_internal-review-aggregator` with:

- **Artifact** — `code`.
- **Scope** — `git diff origin/main`.
- **Plan path** — the plan file, so the `project` reviewer can check
  plan↔implementation drift.

It resolves the code roster (`project` + `official-anthropic-review-skill` always, plus `fallow`,
`ponytail`, and `codex` when enabled and available), runs the reviewers in
parallel, dedups across them, and returns one triaged, source-tagged findings
list (Apply / Decision needed) plus any reviewer skip notes.

Don't fix things you don't understand. When in doubt, leave it for the user to decide and surface it.

### 2. Apply fixes, one commit per fix

For each **Apply** item:

1. Make the change.
2. Re-run any cheap local validators relevant to the change (e.g. `docker compose config -q`, `pnpm test --filter <pkg>`, `tsc --noEmit`) — not the full smoke suite, just what the touched file warrants.
3. `git commit` that fix alone. Commit message: short imperative summary referencing the finding (e.g. `fix(server): drop trailing slash on grafana proxy_pass`). Include the `Co-Authored-By` trailer per the global commit convention.

Do NOT batch multiple fixes into one commit — each fix should be reviewable and revertable in isolation.

### 3. Report to the user

Report using the shared format — applied fixes as the brief one-line-each
mention, then the **Decision needed** findings as the severity breakdown (with
`source` tags), and mention any reviewer skip notes:

<report-format>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/review-report-format.md`
</report-format>

### 4. Close the review

- `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Code review completed"`
- If findings changed the plan, update the plan file and commit it (separate commit).

## Step: User Review

**This is separate from the code review fix selection above - do not skip it.**

Show the user:

```bash
git diff main --stat
```

Present to the user:

- **Implementation overview** - brief summary of what was built and the key decisions made
- **Documentation changes** - one line per doc that was updated
- **Code review findings** - for each finding, show:
  - The finding and how it was addressed (applied or disagreed - and why)
  - A short code snippet showing the problem and how the fix changes it (before/after)

Use `AskUserQuestion` with header "User review" to ask: "Are you happy with the implementation? Review the changes and let me know."

- Options: "Approve" / "Needs changes"

If "Needs changes": discuss, apply, re-commit, and ask again.

**Gate:** Do NOT proceed until the user selects "Approve".

## Wrap Up

1. `${CLAUDE_PLUGIN_ROOT}/bin/tasks flow-progress-set <KEY> Done`
2. `${CLAUDE_PLUGIN_ROOT}/bin/tasks comment <KEY> "Implementation complete - user approved"`
3. Run the `/devflow:start-flow` skill to find the next phase.
