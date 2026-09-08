# Plan Guidelines

The rubric a plan is judged against. Structure and headings are specified in
`plan-format.md`; this doc covers whether the plan is any *good*.

## Completeness

- Every requirement in `## Requirements Brief` / `## Requirements` is addressed somewhere in the plan.
- Nothing is planned that wasn't asked for. No invented behavior, no speculative features, no "while we're here" refactors.
- Decisions rejected during requirements leave no residue anywhere in the plan.
- Open questions are named as open, not silently resolved by the plan author.
- Task Scope matches what Detailed Implementation actually builds - no scope drift between the two.

## Correctness

- Interfaces and data flow work end to end: every consumer of a changed contract is accounted for, and every producer exists.
- Types/schemas line up across boundaries - what one side writes is what the other side reads.
- The event-level story in Key Changes Summary is achievable with the files and contracts listed.
- Storage changes state how existing data is handled (migration, backfill, or "none needed - why").
- Implementation order is buildable: nothing depends on something planned later.

## Consistency with the codebase

- Reuses existing helpers, utils, types, and patterns instead of adding parallel ones.
- Follows the project's developer guidelines and the patterns in the code areas being touched.
- New files land where comparable files already live, with the project's naming conventions.
- Architecture docs relevant to the touched areas were consulted, and the plan doesn't contradict them.

## Testing strategy

- Every capability the task adds or changes is covered by at least one named test level.
- Each behavior is tested at the **lowest level that can exercise it**, and not re-tested above that except for the single path that proves the wiring. If a unit test would catch the bug, an e2e test for it is waste.
- Distribution follows from that rule: most cases are unit, a handful are integration, e2e is one spec per user-facing flow (not per case), manual is the exception.
- Each concern group in Detailed Implementation has its `Tests:` sub-bullet, with happy path plus the edge cases that matter.
- Deliberate gaps are stated with a reason, not left implicit.
- The `## Tests` rollup lists every test file the plan introduces or touches.

### Which level when

- **Unit** - pure logic reachable without I/O: parsing, transforms, validation, reducers, heuristics, formatting. Every branch and edge case belongs here. Default for anything you can call directly.
- **Integration** - the seam between two real parts: a route handler against a temp DB, a pipeline step with the external agent mocked, a component with its store. One happy path plus the failure mode of the boundary (timeout, bad payload, missing row). Mock only external seams - paid APIs, third-party agents, push/deploy; everything owned by the repo runs for real.
- **E2E (browser)** - a **new or changed user-facing flow**: a new screen, a multi-step flow, a changed primary action, or a lifecycle the user actually walks (create → see → edit → persists). One spec per flow: the happy path plus the one failure a user can hit from that screen. Required when the task adds such a flow **and the app already has a harness** (`playwright.config.ts` or equivalent); a task never builds the harness. Not for cosmetic tweaks, copy changes, or behavior already proven at a lower level.
- **Manual** - only what automation genuinely can't reach: visual polish, a third-party consent screen, hardware. State the exact steps so a reviewer can repeat them.

## Risks and edge cases

- Failure paths are planned, not just the happy path: empty state, partial data, concurrent access, network/IO failure, permission denial.
- Anything irreversible (data deletion, migration, external side effect) says how it's guarded or rolled back.
- Performance-sensitive paths (large inputs, N+1 access, hot loops) are called out if the change touches them.
- Backward compatibility is addressed for anything already in use by callers, stored data, or external consumers.

## Hidden dependencies

- Callers outside the listed files that touch the changed contracts are found and included.
- Config, env vars, secrets, feature flags, and build steps the change needs are listed.
- New or upgraded dependencies are justified - and rejected if stdlib, an existing dependency, or a few lines cover it.
- Cross-repo, service, or deploy coordination the change requires is stated.
