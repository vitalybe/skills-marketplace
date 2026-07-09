---
name: _internal-code-review
description: Internal review engine - analyzes changes against project criteria and guidelines and returns triaged findings. Invoked by /devflow:_internal-step-code; not called directly by the user. Does not apply fixes or render a user-facing report - the caller does that.
---

# Internal Code Review Engine

Analyzes a set of changes and returns triaged findings. The **caller** applies
fixes and renders the report; this skill only produces the findings list.

## Inputs (from the caller)

- **Scope** — what changed. Default to `git diff origin/main` if the caller
  gives nothing.
- **Plan path** (optional) — check implementation ↔ plan drift in both
  directions (more shipped than planned, less shipped).
- **Focus areas** (optional) — extra emphasis, e.g. test coverage on new paths.

## Process

```bash
git fetch
git diff origin/main --stat
```

1. Read each changed file for full context - don't review the diff in isolation.
2. Analyze against every criterion below.
3. Triage each finding (see Output).

## Review criteria

- **Correctness** — bugs, logic errors, broken paths.
- **Maintainability** — clarity, modularity, design-pattern fit.
- **Readability** — formatting and comments per project style.
- **Efficiency** — obvious performance or resource problems.
- **Security** — vulnerabilities or unsafe practices.
- **Edge cases & error handling** — failure modes handled.
- **Testability** — new/changed paths covered; suggest missing tests even when preflight passes.
- **Guidelines compliance** — against the developer guidelines below.

<developer-guidelines>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/developer-guidelines.md`
</developer-guidelines>

## Output

Return a findings list using the shared format's severity tiers and
Apply / Decision-needed triage:

<report-format>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/review-report-format.md`
</report-format>

- Tag each finding **Apply** (clear issue, unambiguous fix) or **Decision needed**
  (out of scope, stylistic, or a judgment call). When in doubt, Decision needed.
- For **Apply** items, name the file:line and the exact change so the caller can
  make it without re-deriving.
- Include a one-line summary and, if a plan was given, the plan↔code deltas.

Do **not** apply fixes, commit, or render a user-facing report. Return the data.
