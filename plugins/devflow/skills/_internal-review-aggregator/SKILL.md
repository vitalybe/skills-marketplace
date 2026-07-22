---
name: _internal-review-aggregator
description: Shared review engine - convenes the reviewer roster for a plan or code change, fans the reviewers out in parallel, dedups and triages their findings, and returns one consolidated list. Invoked by the review callers (_internal-step-plan, _internal-step-code, code-review, pr-review); not called directly by the user. Does not apply fixes or render a user-facing report - the caller does that.
---

# Review Aggregator

Convenes several reviewers over one artifact, runs them in parallel, then merges
and triages everything they find into a single list. The **caller** applies
fixes and renders the report; this skill only produces the findings.

## Inputs (from the caller)

- **Artifact** — `plan` or `code`. Selects which reviewers apply. Required.
- **Scope** — what to review. For `code`, a diff (default `git diff origin/main`);
  for `plan`, the plan file path.
- **Plan path** (optional, `code` only) — enables the `project` reviewer's
  plan↔code drift check (both directions: more shipped than planned, less).
- **Focus areas** (optional) — extra emphasis passed through to the reviewers.

## Context

<review-roster>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/review-roster.md`
</review-roster>

<project-config>
!`cat project-config.toml 2>/dev/null || echo "[[no project-config.toml - exclude nothing]]"`
</project-config>

<doctor>
!`${CLAUDE_PLUGIN_ROOT}/bin/doctor 2>&1 || true`
</doctor>

<developer-guidelines>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/developer-guidelines.md`
</developer-guidelines>

## Process

### 1. Resolve the roster

Apply the roster doc's **Resolving the roster** rules to the current artifact,
using the injected `project-config.toml` (the `[review] exclude` list) and the
`doctor` output (dependency availability). Keep a one-line skip note for every
reviewer dropped by an exclude or a missing dependency.

### 2. Read the artifact for context

```bash
git fetch
git diff origin/main --stat   # code artifact
```

For `code`, read each changed file in full - don't review the diff in isolation.
For `plan`, read the whole plan file plus the requirements/context the caller
passed.

### 3. Run the selected reviewers in parallel

In a **single message**, dispatch every selected reviewer per its "how to run"
entry in the roster:

- The built-in lanes (`project`, `plan`) — do this analysis yourself. `project`
  uses the developer-guidelines above (and the plan path, if given, for drift);
  `plan` uses the plan-quality rubric.
- Sub-agent lanes (`official-anthropic-review-skill`, `ponytail`, `codex`) — spawn one sub-agent each.
- `fallow` — run the CLI directly (no sub-agent) and parse its diagnostics.

Wait for all lanes to return.

### 4. Normalize, dedup, triage

Normalize every finding to the shared shape (severity · location · issue ·
suggested change) with a **`source`** = the reviewer id. Then merge per the
roster's **Normalizing and merging** rules: dedup across sources (corroborating
sources listed together), respect each reviewer's mandate.

Triage each merged finding:

- **Apply** — clear issue, unambiguous fix. Name the file:line and the exact
  change so the caller can make it without re-deriving.
- **Decision needed** — out of scope, stylistic, or a judgment call. When in
  doubt, Decision needed.

## Output

Return, as data (not a rendered report):

- The **triaged findings** using the shared format's severity tiers and
  Apply / Decision-needed split, each tagged with its `source`(s).

  <report-format>
  !`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/review-report-format.md`
  </report-format>

- A one-line **summary**, and - if a plan path was given - the plan↔code deltas.
- The **skip notes** from step 1 (which reviewers didn't run and why).

Do **not** apply fixes, commit, or render a user-facing report. Return the data
to the caller.
