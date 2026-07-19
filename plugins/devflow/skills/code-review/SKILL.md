---
name: code-review
description: Reviews the current changes against main and reports findings. Use when the user asks to "code review", "review my changes", or "review this branch" without a specific PR number. Runs the internal review engine, applies obvious fixes, and presents a structured breakdown.
---

# Code Review

Review the working changes against `main`, fix the obvious findings inline, then
report.

## Phase 1: Review

Invoke `/devflow:_internal-code-review`. Pass any focus areas the user gave (and a
plan path if one is in play). It returns triaged findings — **Apply** vs
**Decision needed**.

While it runs, skim `git diff origin/main --stat` yourself for the summary.

## Phase 2: Apply obvious fixes

For each **Apply** finding — anything a careful committer would fix without
discussion (typos, broken imports, type errors, dead code, clear logic bugs):

- One commit per logical fix; stage only its files (never `git add -A`).
- Match the repo's commit style (`git log -5 --oneline`).
- Re-run the cheap validator the change warrants (`tsc --noEmit`,
  `pnpm test --filter <pkg>`). If a fix doesn't pass, leave it as a
  Decision-needed suggestion instead.

Leave subjective design, missing tests, scope, and architecture for the report.

## Phase 3: Report

Present using the shared report format:

<report-format>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/review-report-format.md`
</report-format>

- **Summary** — 2-4 sentences: what changed, its shape, and a one-line recommendation.
- **Applied fixes** — the brief one-line-each mention (per the format), before the breakdown.
- **Findings** — the **Decision needed** items, grouped by severity.
