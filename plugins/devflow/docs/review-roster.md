# Review roster

The set of reviewers the aggregator can convene, and the rules for deciding
which ones actually run for a given review. The aggregator
(`_internal-review-aggregator`) reads this to build the roster, then fans the
selected reviewers out in parallel and merges their findings.

## Reviewers

Each reviewer has a **mandate** (the lane it owns - kept non-overlapping so the
merge doesn't drown in duplicates), the **artifact** it applies to, its
**dependency**, and **how the aggregator runs it**.

| id                                | artifact   | mandate                                                                                                                                                                    | dependency                                | how to run                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| --------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `plan`                            | plan       | Plan quality per `${CLAUDE_PLUGIN_ROOT}/docs/plan-guidelines.md` - completeness, correctness, codebase consistency, test strategy, risks, hidden dependencies.              | none (aggregator itself)                  | The aggregator's own analysis of the plan file, reading `${CLAUDE_PLUGIN_ROOT}/docs/plan-guidelines.md` as its review criteria.                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| `official-anthropic-review-skill` | code       | Generic correctness recall - bugs a project-specific pass might miss - plus project developer-guidelines compliance and, when a plan path is given, plan↔code drift (both directions). | none                                      | Sub-agent. Invokes the **built-in** Claude Code code-review skill at `high` effort - the built-in one, **not** `/devflow:code-review` (the names collide). The same sub-agent also reads `${CLAUDE_PLUGIN_ROOT}/docs/developer-guidelines.md` itself and reviews the diff against those guidelines, and when a plan path is given checks plan↔code drift in both directions (shipped-but-unplanned, planned-but-unshipped).                                                                                                                                                                          |
| `fallow`                          | code       | Deterministic static analysis: dead code, duplication, complexity, architecture drift.                                                                                     | `node`/`npx`; **TS/JS files in the diff** | Run `npx fallow dead-code`, `npx fallow dupes`, `npx fallow health` **bare - fallow scans the whole project and takes no path/file arguments** (passing a path errors with `unexpected argument`); then keep only the diagnostics that fall in the changed TS/JS files. Not an LLM lane - run the CLI directly, no sub-agent.                                                                                                                                                                                                                                                                    |
| `ponytail`                        | code, plan | Simplification / anti-over-engineering ("does this need to exist? already in the codebase? one line?").                                                                    | ponytail plugin installed                 | Sub-agent invokes `/ponytail-review` scoped to the diff (code) or the plan file (plan). Mandate is simplification only - do not re-report ordinary bugs.                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `codex`                           | code, plan | Cross-model (GPT-family) correctness second opinion - breaks Claude's shared blind spots.                                                                                  | codex CLI + `codex login`; the doctor checks the CLI only | Sub-agent runs `codex exec` headless, pinned to `-m gpt-5.6-sol`. Code: `codex exec review --base main -m gpt-5.6-sol` (the repo's default branch) for correctness; **and when a plan path is given, also run** `codex exec -m gpt-5.6-sol "<prompt: compare the diff (git diff main) against the plan at <plan_path>; report implementation↔plan drift both directions - shipped-but-unplanned and planned-but-unshipped>"`, merging both into codex findings. Plan artifact: `codex exec -m gpt-5.6-sol "<plan-review prompt pointing at the plan file>"`. Normalize its output into findings. |

## Resolving the roster

Given the **artifact** (`plan` or `code`), the injected **project-config.toml**,
and the injected **doctor** output, build the run list:

1. **Start** with every reviewer whose `artifact` column includes the current
   artifact. The artifact's **baseline lane** - `official-anthropic-review-skill`
   for `code`, `plan` for `plan` - always runs. It is never dropped by an
   exclude or a dependency check, so steps 2 and 3 apply only to the optional
   lanes (`fallow`, `ponytail`, `codex`), which layer on when enabled and
   available.
2. **Subtract excludes.** Remove any optional lane listed in `[review] exclude`
   in `project-config.toml` (a single list; it applies to whichever phase a
   reviewer participates in). Missing/empty `[review]` block = exclude nothing.
3. **Subtract unmet dependencies.** Remove any optional lane whose dependency
   the doctor output reports as absent - `fallow` (no `node`, or no TS/JS files
   in the diff), `ponytail` (plugin not installed), `codex` (CLI not found).
4. **Record every drop.** For each reviewer removed in step 2 or 3, keep a
   one-line note (`skipped <id> - excluded` / `skipped <id> - <dep> not found`)
   so the aggregator can surface it. A reviewer being unavailable is **never** a
   hard error - the review proceeds with whoever is left.

## Normalizing and merging findings

Every reviewer's output is normalized to the shared finding shape - severity
tier, location, issue, suggested change - plus a **`source`** = the reviewer id
that raised it.

- **Dedup across sources.** Same defect at the same location from more than one
  reviewer → keep one item, merge the strongest description, and set its
  `source` to all that raised it (e.g. `source: official-anthropic-review-skill, codex`) as
  corroboration.
- **Respect mandates.** If a reviewer strays outside its lane (e.g. `ponytail`
  reports a plain bug), keep the finding but attribute it accurately; don't
  discard signal, but don't let one defect appear five times.

The aggregator returns the merged, triaged list. It does **not** apply fixes or
render the user-facing report - the calling skill does that.
