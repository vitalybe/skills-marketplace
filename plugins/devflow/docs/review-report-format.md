# Review report format

A review report lists its items (findings, deltas, etc.) grouped under fixed
severity tiers. Start each item with a short bold title (2-5 words) on its own
line, then render its details as bold-labeled fields beneath it — never a
markdown table. The invoking skill names the fields; linkify file paths like
`[file.ts:123](path/to/file.ts:123)`.

Prefix each finding's title with a short id `Q<n>` (`Q1`, `Q2`, …), numbered
sequentially across the whole findings list — starting at `Q1` in the top
severity tier and continuing unbroken through the lower tiers — so the user can
reference any item by its id (e.g. `Q1 - Unindexed user lookup`). The Q-ids
cover the findings/Decision-needed list only, not the Applied-fixes one-liners.

These are also the gate-package question ids: a report presented at a gate asks
for a decision per finding, and the answers come back keyed by these same ids.

## Severity tiers

- 🔴 **Critical** — blocks the artifact from working.
- 🟠 **High** — silent breakage; works but the intent fails on a realistic path.
- 🟡 **Medium** — robustness, clarity, or completeness; can ship without it.
- 🟢 **Low** — polish, wording, style.

Render each tier at most once, in the fixed order above, and group all of that
tier's items under its single header — never split a tier across multiple
headers. Omit a tier entirely when it has no items (don't emit an empty
"(none)" header) unless the invoking skill says otherwise. When one
severity-grouped list mixes item kinds (e.g. code findings alongside plan↔code
deltas), tag each item inline with its kind — e.g. a `(plan delta)` suffix on
the title — so a shared tier stays unambiguous. The invoking skill may add a
one-line domain gloss per tier, but the tiers and emoji are fixed.

## Apply / Decision needed triage

When triaging findings, sort each into **Apply** (clear issue, unambiguous fix)
or **Decision needed** (out of scope, stylistic, or a judgment call for the
user). Don't apply changes you don't understand — when in doubt, mark it
Decision needed and surface it.

Applied fixes are **not** part of the severity breakdown. Mention them briefly —
one line each — under an **Applied fixes** heading *before* the breakdown, then
give the full severity breakdown for the **Decision needed** items only. If
nothing was applied, write "Applied fixes: none." (In the flow's review phases
the breakdown goes to the plan file, not to chat — see below.)

## Source attribution

When findings come from more than one reviewer (see the review roster), tag each
finding with a **Source** field naming the reviewer id(s) that raised it. When
several reviewers raised the same defect, list them together as corroboration
(e.g. **Source.** official-anthropic-review-skill, codex). Omit the field entirely for single-reviewer
reviews where attribution adds nothing.

## Recording review outcomes in the plan

The flow's review steps (`_internal-step-plan`, `_internal-step-code`) also
record the review in the plan file - and for those steps the plan is the *only*
place the finding bodies go: the gate names them by id and the question the user
gets carries the body read back from the plan. The plan entries reuse the
severity tiers, `Q<n>` ids, and source attribution above, so a finding carries
the same id in the plan, at the gate, and in the answers coming back.

- **Applied findings never enter the plan.** Findings the agent fixed itself
  (the Apply tier) appear in the chat report only.
- **Decision-needed findings are written to `### Unhandled`** before they go to
  the user - under `## Plan review findings` for a plan review, `## Code review
  findings` for a code review. This write is the gate's flush. Then ask the
  user about them, one question per finding.
- **After the user responds**, move each decided finding to `### Handled` with
  the decision recorded:
  - *fixed as requested* - then implement it;
  - *rejected* - with the user's reason;
  - *question* - with its answer.
- **Findings the user ignored or skipped** (e.g. "go to the next phase" without
  addressing them) stay under `### Unhandled` as-is.

`### Unhandled` is the live list of open items. The plan must carry the
decisions the user took before the phase completes.

## Example

**Applied fixes**

- [src/auth.ts:42](src/auth.ts:42) — fixed token-expiry unit mismatch (s vs ms). `a1b2c3d`

**Findings** (Decision needed)

### 🟡 Medium

**Q1 - Unindexed user lookup**
- **Location.** [src/db.ts:88](src/db.ts:88)
- **Source.** official-anthropic-review-skill, codex
- **Issue.** The query runs without an index on `user_id`.
- **Options.** (a) add the index in this task's migration; (b) file a follow-up and ship as-is; (c) leave it — the table stays small.
- **Why not applied.** Out of scope for this change; needs a migration review.
- **Implication if not addressed.** Slower lookups as the table grows.

**Q2 - Silent JSON parse failure**
- **Location.** [src/api.ts:120](src/api.ts:120)
- **Issue.** A malformed payload is swallowed and returns an empty result.
- **Options.** (a) surface a 400 with the parse error; (b) keep the empty result and log it.
- **Why not applied.** Changes the API contract; needs product sign-off.
- **Implication if not addressed.** Clients can't tell a bad request from an empty one.
