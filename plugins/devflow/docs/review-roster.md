# Review roster

The set of reviewers the aggregator can convene, and the rules for deciding
which ones actually run for a given review. The aggregator
(`_internal-review-aggregator`) reads this to build the roster, then fans the
selected reviewers out in parallel and merges their findings.

## Reviewers

Each reviewer has a **mandate** (the lane it owns - kept non-overlapping so the
merge doesn't drown in duplicates), the **artifact** it applies to, its
**dependency**, and **how the aggregator runs it**.

| id | artifact | mandate | dependency | how to run |
|---|---|---|---|---|
| `project` | code | Project developer-guidelines compliance + plan↔code drift (both directions). | none (built-in) | The aggregator's own analysis against the developer-guidelines (injected by the caller) and, when a plan path is given, plan-vs-code deltas. |
| `plan` | plan | Plan-quality rubric: completeness, correctness of interfaces/data-flows, consistency with codebase patterns, test-strategy coverage, risk/edge-cases, hidden dependencies. | none (built-in) | The aggregator's own analysis of the plan file against the rubric above. |
| `generic` | code | Generic correctness recall - bugs a project-specific pass might miss. | none (built-in) | Sub-agent invokes the built-in `/code-review` skill at `high` effort. Does not need the plan. |
| `fallow` | code | Deterministic static analysis: dead code, duplication, complexity, architecture drift. | `node`/`npx`; **TS/JS files in the diff** | Run `npx fallow dead-code`, `npx fallow dupes`, `npx fallow health` scoped to the changed TS/JS files; parse the diagnostics into findings. Not an LLM lane - run the CLI directly, no sub-agent. |
| `ponytail` | code, plan | Simplification / anti-over-engineering ("does this need to exist? already in the codebase? one line?"). | ponytail plugin installed | Sub-agent invokes `/ponytail-review` scoped to the diff (code) or the plan file (plan). Mandate is simplification only - do not re-report generic bugs. |
| `codex` | code, plan | Cross-model (GPT-family) correctness second opinion - breaks Claude's shared blind spots. | codex CLI + Codex MCP configured + provider auth | Sub-agent sends the diff (code) or plan file (plan) to the Codex MCP review tool with a correctness-review prompt; normalize its output into findings. |

## Resolving the roster

Given the **artifact** (`plan` or `code`), the injected **project-config.toml**,
and the injected **doctor** output, build the run list:

1. **Start** with every reviewer whose `artifact` column includes the current
   artifact.
2. **Subtract excludes.** Remove any id listed in `[review] exclude` in
   `project-config.toml` (a single list; it applies to whichever phase a
   reviewer participates in). Missing/empty `[review]` block = exclude nothing.
3. **Subtract unmet dependencies.** Remove any reviewer whose dependency the
   doctor output reports as absent - `fallow` (no `node`, or no TS/JS files in
   the diff), `ponytail` (plugin not installed), `codex` (CLI/MCP/auth missing).
   The built-in lanes (`project`, `plan`, `generic`) have no dependency and are
   never dropped here.
4. **Record every drop.** For each reviewer removed in step 2 or 3, keep a
   one-line note (`skipped <id> - excluded` / `skipped <id> - <dep> not found`)
   so the aggregator can surface it. A reviewer being unavailable is **never** a
   hard error - the review proceeds with whoever is left.

The always-on baseline: `code` reviews always run at least `project` + `generic`;
`plan` reviews always run at least `plan`. The other lanes layer on when enabled
and available.

## Normalizing and merging findings

Every reviewer's output is normalized to the shared finding shape - severity
tier, location, issue, suggested change - plus a **`source`** = the reviewer id
that raised it.

- **Dedup across sources.** Same defect at the same location from more than one
  reviewer → keep one item, merge the strongest description, and set its
  `source` to all that raised it (e.g. `source: generic, codex`) as
  corroboration.
- **Respect mandates.** If a reviewer strays outside its lane (e.g. `ponytail`
  reports a plain bug), keep the finding but attribute it accurately; don't
  discard signal, but don't let one defect appear five times.

The aggregator returns the merged, triaged list. It does **not** apply fixes or
render the user-facing report - the calling skill does that.
