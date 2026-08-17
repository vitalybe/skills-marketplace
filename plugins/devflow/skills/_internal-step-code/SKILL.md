---
name: _internal-step-code
description: Implement the plan for a development task, run tests, and do a code review. Use when the plan is approved and it's time to write code, or when the user invokes /devflow:_internal-step-code. Also trigger on phrases like "implement this", "start coding", "build it", "write the code". Includes sub-agent code review and user approval. This is phase 3 of the dev task flow.
---

# Implementation & Code Review

User input goes through gates - see **Gates** in the common instructions
below.

## General

<common-instructions>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/flow-common-start.md`
</common-instructions>

## Step: Read the Plan

Read the full plan from the path injected in `<plan-path>` (see
Environment details above). If implementation reveals the plan needs
adjustment, edit that file (not the issue description), re-confirm
with the user, then commit the plan file.

**Resume:** the plan's `## Code Review Findings` says where to re-enter.
Findings with no decision recorded - go to **Step: User Review** and present
them. Decisions recorded but not carried out - implement them, then continue
from there.

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
- **Fresh worktree? Install deps first.** A per-task git worktree starts
  with no `node_modules`, so the first `pnpm test`/`pnpm build` fails with
  `vitest: command not found` / `tsc: command not found`. That's a missing
  install, not a test failure - run `[ -d node_modules ] || pnpm install`
  (or the project's `npm ci` / `pnpm install`) before the first run.
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

## Step: Code Review

Run the review roster via the aggregator, then apply and report.

### 1. Run the review

Invoke `/devflow:_internal-review-aggregator` with:

- **Artifact** - `code`.
- **Scope** - the branch's own changes since it forked:
  `git diff "$(git merge-base origin/main HEAD)" HEAD`. Not plain
  `git diff origin/main` / `git diff main` - the aggregator explains why.
- **Plan path** - the plan file, so the `official-anthropic-review-skill` lane
  can check plan↔implementation drift.

It resolves the code roster (see `${CLAUDE_PLUGIN_ROOT}/docs/review-roster.md`),
runs the lanes in parallel, dedups across them, and returns one triaged,
source-tagged findings list (Apply / Decision needed) plus any reviewer skip
notes.

Don't fix things you don't understand. When in doubt, leave it for the user to decide and surface it.

### 2. Apply fixes, one commit per fix

For each **Apply** item:

1. Make the change.
2. Re-run any cheap local validators relevant to the change (e.g. `docker compose config -q`, `pnpm test --filter <pkg>`, `tsc --noEmit`) - not the full smoke suite, just what the touched file warrants.
3. `git commit` that fix alone. Commit message: short imperative summary referencing the finding (e.g. `fix(server): drop trailing slash on grafana proxy_pass`). Include the `Co-Authored-By` trailer per the global commit convention. For any multi-line message, write it to a temp file first (`/tmp/claude-<epoch-millis>.md`, a unique name to avoid colliding with a stale file) and `git commit -F` it - don't pass it via heredoc/`printf`/`echo`.

Do NOT batch multiple fixes into one commit - each fix should be reviewable and revertable in isolation.

### 3. Write the decision-needed findings into the plan

Record the **Decision needed** findings in the plan's `## Code Review Findings`
section, and update the plan itself if a finding changed it. Commit the plan file
(separate commit).

<report-format>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/review-report-format.md`
</report-format>

### 4. Report to the user

Report using the shared format above - applied fixes as the brief one-line-each
mention, then the **Decision needed** findings as the severity breakdown (with
`source` tags), and mention any reviewer skip notes.

## Step: User Review

**This is separate from the code review fix selection above - do not skip it.**

Show the user:

```bash
git diff "$(git merge-base origin/main HEAD)" --stat
```

Present to the user:

- **Implementation overview** - brief summary of what was built and the key decisions made
- **Documentation changes** - one line per doc that was updated
- **Code review findings** - for each finding, show:
  - The finding and how it was addressed (applied or disagreed - and why)
  - A short code snippet showing the problem and how the fix changes it (before/after)

Ask: "Are you happy with the implementation? Approve, or tell me what to change -
including what to do about each Decision-needed finding", keyed by each
finding's `Q<n>` id.

End the gate turn with the diff overview, the before/after findings, and that
approval question as the package - it is presented as written, so word it for
the user. Writing the decision-needed findings into `## Code Review Findings`
in the step above is this gate's flush.

If changes are wanted: apply them, re-commit, and ask again.

**Gate:** Do NOT proceed until the user approves.

## Step: Record the Review Decisions

Once the answers are in, record each finding's outcome in the plan's
`## Code Review Findings` section per the **Recording review outcomes in the
plan** procedure in the report format above: implement the fixes the user asked
for, note rejections with their reason and questions with their answer, and move
anything the user ignored to `### Unhandled`. Commit the plan file. This phase
does not complete until the plan carries all of it.

## Wrap Up

1. Make sure every change is committed, the plan file included.
2. Report completion: what was built, the commits, and the plan file path.
