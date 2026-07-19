---
name: git-commit
description: Examine uncommitted changes and split them into logical, well-scoped git commits. Handles untracked files by either staging them or adding them to .gitignore. Runs on haiku in a forked subagent; reports back what it did and any open questions.
context: fork
agent: general-purpose
model: haiku
---

# Git Logical Commits

Split the current working-tree changes into a series of small, logical commits. Each commit should represent one coherent change (a single feature, fix, refactor, or doc update) so the history is easy to read and revert.

## Workflow

### 1. Survey the state

Run these in parallel:

```bash
git status
git diff
git diff --staged
git log -n 10 --oneline
```

Use `git log` only to match the repo's commit-message style (tense, prefixes like `fix:` / `feat:`, capitalization). Do not copy unrelated content.

Never use `git status -uall` (memory issues on large repos).

### 2. Handle untracked files

For each untracked file, classify it:

- **Should be committed** (source code, docs, configs that belong in the repo) -> stage it with `git add <path>` as part of a matching logical commit below.
- **Should be ignored** (build output, `node_modules/`, `.env`, `*.log`, `.DS_Store`, editor caches, local-only artifacts) -> add the appropriate pattern to `.gitignore` and stage that `.gitignore` change.
- **Unsure** -> LEAVE UNSTAGED. Record the file path and your uncertainty in the final report so the parent/user can decide. Do not commit it.

Never commit files that likely contain secrets (`.env`, `credentials.json`, private keys, tokens). If such a file is present, leave it unstaged and flag it prominently in the final report.

### 3. Plan logical commits

Group all changes (already-tracked edits + newly staged untracked files) into logical commits. Guidelines:

- One commit = one logical change. Don't lump an unrelated refactor into a bug fix.
- Keep commits small but self-contained. A commit should compile/run on its own when possible.
- Common groupings:
  - feature + its tests + its docs -> one commit
  - unrelated fix -> separate commit
  - formatting / rename sweep -> separate commit
  - dependency bump -> separate commit
  - `.gitignore` additions -> separate commit (or fold into the commit that introduced the ignored paths)
- If changes inside a single file belong to different logical commits, use `git add -p <file>` (patch mode) to stage hunks selectively.

Briefly list the planned commits to the user before creating them (title + files). If the plan is obvious and low-risk (e.g. a single clear commit), skip the preview and just commit.

### 4. Create the commits

For each planned commit:

1. Stage only the files/hunks for that commit.
2. Write the commit message to `/tmp/claude-<epoch-ms>.md` using the Write tool (per the user's global instructions - never use heredocs / `echo` / `$()`).
3. Commit with `git commit -F /tmp/claude-<epoch-ms>.md`.
4. Run `git status` to confirm the working tree state before moving to the next commit.

Commit message format:

- Subject line: concise, imperative mood, under ~70 chars. Match existing repo style (check `git log --oneline`).
- Optional body: explain *why*, not *what*, if the subject isn't self-explanatory.
- Trailer (always):

  ```
  Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>
  ```

### 5. Report back to the parent

You are running in a forked subagent with no conversation access. The main model cannot see your steps - it only sees your final message. Structure the report as:

**Done:**
- Number of commits created
- Output of `git log --oneline -n <N>` for the new commits

**Left unstaged (if any):**
- File path + reason (e.g. "could be scratchpad, could be doc - needs user decision")
- Files that look secret-like, named explicitly

**Questions / considerations for the main model:**
- Ambiguous grouping decisions you made (what you chose, what the alternative was)
- Commit scope concerns (e.g. "I lumped X and Y because they touch the same file, but they're logically separate - reverse if you disagree")
- Anything about the working tree that seemed unusual

Keep the report tight - the parent will relay it to the user, so no filler.

## Safety Rules

- **Never** run `git push`, `git reset --hard`, `git commit --amend`, `git rebase`, or any destructive op. This skill only stages and commits.
- **Never** use `git add -A` or `git add .`. Stage files by explicit path.
- **Never** skip hooks (`--no-verify`). If a pre-commit hook fails, fix the issue and create a NEW commit - do not amend.
- **Never** modify files to make a commit cleaner without telling the user. Edits beyond staging (e.g. running a formatter) require explicit user consent.
- If the working tree is clean (nothing to commit), say so and stop.

## No Interactive Questions

You run in a forked subagent - you cannot pause and ask the user. Anywhere the workflow says "ask the user", instead:

- Make the safest available choice (don't stage ambiguous files, don't commit secrets, skip risky groupings)
- Record what you did and what alternatives existed in your final report
- Let the parent/user course-correct after seeing the report

Never stall waiting for input that won't come.
