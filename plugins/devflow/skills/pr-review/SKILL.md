---
name: pr-review
description: Reviews a GitHub pull request against its plan file, inside a worktree, using the shared review roster. Use whenever the user asks to "review PR #N", "code-review PR #N", "do a PR review on #N", "look over PR #N", or names a specific PR number with review intent. Performs the full ritual - checkout, rebase, plan lookup, review via the aggregator (project/official-anthropic-review-skill/fallow/ponytail/codex), fix-and-commit for obvious findings, then a structured report. Always use this skill when a specific PR number is mentioned with review intent; don't do PR reviews ad-hoc.
---

# PR Review

Review a GitHub PR against its plan file, inside a worktree so the user's main
checkout is untouched. This skill does **not** create the worktree - it requires
the session to already be in one and refuses otherwise. Fix obvious findings
inline (one commit each), then report. Posting comments, pushing, and merging
stay with the user.

## Inputs

- **PR number** (required) — ask if not given.
- **Focus areas** (optional) — pass through to the aggregator verbatim.

## Phase 1: Prepare

1. **Require a worktree.** This skill runs inside an existing worktree; it does
   not create one. Refuse to run from the main repo:
   ```bash
   [ "$(git rev-parse --git-common-dir)" = "$(git rev-parse --git-dir)" ] && echo "main-repo" || echo "worktree"
   ```
   If this prints `main-repo`, **stop**. Tell the user to create and enter a
   worktree first (e.g. `git worktree add .worktrees/pr-<N>` then the
   **EnterWorktree** tool, `path: .worktrees/pr-<N>`), and re-run from there.

2. **Fetch PR metadata:**
   ```bash
   gh pr view <N> --json number,title,headRefName,baseRefName,body,state,url,author
   ```
   Note the head branch (`<headRefName>`). If the PR is closed/merged, tell the
   user and ask whether to review anyway.

3. **Check out the PR branch** (in the current worktree):
   ```bash
   git fetch origin
   git checkout -B <headRefName> origin/<headRefName>
   ```

4. **Rebase and set up:**
   ```bash
   git pull --rebase origin main
   ```
   Then run the project's install/setup step if it has one (`pnpm install`,
   `npm ci`, `uv sync`, …); skip if the project needs none. Resolve trivial
   rebase conflicts silently; stop and ask if a conflict touches the PR's logic
   or needs judgment.

5. **Find the plan.** Pull the task key from the PR title/body and run
   `${CLAUDE_PLUGIN_ROOT}/bin/tasks plan <KEY>`. If no path, parse the PR body
   for a `_plans/...md` link; last resort, ask the user. Show the resolved plan
   path before continuing. If there genuinely is no plan, proceed without one
   (the aggregator handles a missing plan path).

## Phase 2: Review

Invoke `/devflow:_internal-review-aggregator` with:

- **Artifact** — `code`.
- **Scope** — the PR's changes, diffed against the merge-base of the branch and
  `origin/main` (not `origin/main`'s tip - if it has advanced past the branch
  point, diffing its tip pulls in unrelated commits):
  ```bash
  git diff "$(git merge-base origin/main HEAD)"
  ```
- **Plan path** — the resolved plan (enables plan↔code drift, both directions:
  more shipped than promised, less shipped).
- **Focus areas** — anything the user passed, plus diff-stat areas of interest
  (new dirs, scope-creep files, files outside the plan).

It resolves the code roster and returns one triaged, source-tagged findings list
(Apply / Decision needed), the plan↔code deltas, and any reviewer skip notes.
While it runs, read the plan and diff stat yourself for the report tables.

## Phase 3: Fix obvious findings

Apply the aggregator's **Apply** items - anything a careful committer would fix
without discussion (failing tests from fixture drift, broken imports, type
errors, typos, dead code, clear logic bugs). Leave subjective design, missing
tests, scope, and architecture for the report.

- One commit per logical fix; stage only its files (never `git add -A`).
- Match the repo's commit style (`git log -5 --oneline`). Write the message to a
  temp file and `git commit -F` it. End every commit with the co-author trailer
  from the global commit convention.
- Revert stray `pnpm-lock.yaml` / `package-lock.json` churn before committing.
- Re-run the touched files' tests (and a type-check for the package if the
  project has one). If a fix doesn't pass, leave it as a report suggestion
  instead.

## Phase 4: Report

Present these sections, in order, using the shared report format:

<report-format>
!`${CLAUDE_PLUGIN_ROOT}/bin/mdexec ${CLAUDE_PLUGIN_ROOT}/docs/review-report-format.md`
</report-format>

- **Summary** — lead with a link to the plan: the GitHub blob URL on the PR's
  head branch (`https://github.com/<org>/<repo>/blob/<headRefName>/<plan_path>`)
  plus the task-key link if there is one. Then 1-2 paragraphs recapping the
  plan's *content* — the problem it targets and the approach it prescribes. This
  frames what the PR set out to do; it is not yet a review of the code.
- **PR overview** — a bird's-eye view of how the PR actually realizes the plan.
  Do **not** repeat the Summary's plan recap. Cover three things:
  - The shape of the change — new modules, rewrites, and where the change
    threads through the codebase.
  - **Sensitive parts to focus on** — the load-bearing or risky areas a reviewer
    should scrutinize (cross-tier contracts, ordering/determinism assumptions,
    thin-coverage paths). Omit if genuinely none.
  - A short **summary of the findings** — the severity headline plus counts
    (e.g. "no Critical/High; two Medium, four Low, one safe Apply").
- **Applied fixes** — the brief one-line-each mention (per the format), before
  the breakdown.
- **Findings & deltas** — ONE severity-grouped list of the **Decision needed**
  items, combining code findings *and* plan↔code deltas. Omit empty tiers.
  Prefix each item's title with a short id `Q<n>` (e.g. `Q1 - Duplicated "All
  employees" heading`), numbered sequentially across the whole list — starting
  at Q1 in the top tier and continuing unbroken through the lower tiers — so the
  user can reference any item by its id. Tag each finding with its `source`(s),
  and each plan delta inline with a `(plan delta)` suffix on its title so it's
  distinct from a code finding in a shared tier. Code findings use the format's
  standard fields; plan deltas use **Plan said**, **Code shipped**,
  **Implication**, **Suggested fix** (or "Fixed inline" / "Skipped"), and cover
  both directions. When there's no plan, just list code findings. After the
  list, on its own line, give the plan's relative repo path as plain text — not
  a link.
- **Reviewers skipped** — one line for any roster reviewer that didn't run
  (excluded or dependency missing), if any.
- **Files changed in this review** — bulleted, linkified, one-line rationale per
  file you modified in Phase 3. End with: worktree path
  (`git rev-parse --show-toplevel`), branch `<headRefName>`.

Stop after the report. Leave the worktree in place. Posting comments, pushing,
tagging reviewers, task-tracker transitions, and merging are separate asks.
