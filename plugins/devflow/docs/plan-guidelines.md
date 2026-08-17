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
- Levels are appropriate - unit for logic, integration for wiring, e2e for user-facing lifecycles, manual only when automation genuinely can't reach.
- Each concern group in Detailed Implementation has its `Tests:` sub-bullet, with happy path plus the edge cases that matter.
- Deliberate gaps are stated with a reason, not left implicit.
- The `## Tests` rollup lists every test file the plan introduces or touches.

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
