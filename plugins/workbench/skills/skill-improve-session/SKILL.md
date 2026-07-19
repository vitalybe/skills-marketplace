---
name: skill-improve-session
description: Review a session transcript to find and fix skill, doc, CLAUDE.md, script, or permission failures. Use when the user wants to improve their setup based on how a recent session went - phrases like "fix this session", "what went wrong", "improve the skill that failed here", "why did that take so many tries", or after a session where a skill/doc misfired. Analyzes the transcript, categorizes the failures, and applies the low-risk fixes.
argument-hint: [session-id] [description of specific problem to fix]
---

# Improve from a session

Analyze a Claude Code session transcript to find and fix issues - skill failures,
missing automations, permission friction, wrong docs, and opportunities for new
skills - then apply the low-risk fixes.

## Arguments

- **session-id** (optional) - UUID of the session to analyze. If omitted, auto-detect the most recent completed session for the current project.
- Free-text describing the specific problem to fix (optional - if omitted, performs a full review).

## Workflow

### 1. Resolve the session

If no session-id was provided, find it:

```bash
# Project dir name = cwd path with / replaced by -
PROJECT_DIR="$HOME/.claude/projects/$(pwd | tr '/' '-')"
# Get the most recent .jsonl files (excluding the current session)
ls -t "$PROJECT_DIR"/*.jsonl | head -5
```

Pick the most recent session. If ambiguous, show the user the last few sessions with their first user message so they can pick.

### 2. Parse the session transcript

The parser is bundled with this skill. Install its deps once (the skill ships
its own `package.json` + lockfile), then run it directly with `npx tsx`:

```bash
SKILL="${CLAUDE_PLUGIN_ROOT}/skills/skill-improve-session"
[ -d "$SKILL/node_modules" ] || pnpm install --dir "$SKILL"
npx tsx "$SKILL/parse-session.ts" --session <session-id>
```

This outputs a markdown conversation summary to stdout.

### 3. Read and analyze the summary

Read the parser output and look for the following categories of issues:

#### A. Overcomplicated actions that should be scripts

Look for multi-step bash sequences, piped commands, or repeated tool patterns that could be wrapped into a reusable script in `bin/` or a skill script. Examples:
- Complex `curl | jq | sed` pipelines
- Multi-step git workflows repeated across sessions
- Data transformations done inline that could be a CLI tool

#### B. Errors, confusion, or pitfalls the agent hit

Look for:
- Wrong CLI flags/syntax - model guessed instead of reading docs
- Repeated attempts at the same operation with different guesses (wasted turns)
- Hallucinated behavior - model assumed how a tool works
- Missing context - skill linked to a reference "if needed" but the model skipped it
- Skipped references - the model didn't read a shared file that had the answer
- Missing error recovery in skills (no "Common Mistakes" section)

For each, check if the relevant skill was invoked and whether adding a warning or common-mistakes entry would prevent recurrence. **Only propose changes that are general enough to help future sessions** - skip one-off edge cases.

#### C. Suggestions for new or updated skills

Look for:
- Operations the user asked for that no existing skill covers
- Patterns that appeared multiple times and could be automated
- Existing skills that were invoked but lacked needed functionality

#### D. Permission friction

If the user complained about permissions, or the transcript shows repeated approval prompts for the same tool pattern:
- Read the permission settings hierarchy:
  - `~/.claude/settings.json` (global)
  - `<project>/.claude/settings.json` (project-level)
- Identify tool patterns that were used multiple times and could be added to the allow list
- Suggest specific permission entries to add

### 4. Read the relevant skill/doc files

Read the skill, doc, and `CLAUDE.md` files that were involved in the failures to
understand their current state before proposing edits.

### 5. Present findings and the fixes

Organize findings by category (A-D above). For each finding: quote the relevant
part of the transcript, explain the issue, and propose a specific fix with
rationale. The concrete fixes usually take one of these shapes:

- **Add missing syntax** to a SKILL.md's common-operations section.
- **Add a Common Mistakes section** (or entry) for a gotcha the model hit.
- **Replace an optional link with dynamic injection** (`` !`cat <file>` ``) so the
  model always sees the reference instead of choosing whether to open it.
- **Add an explicit warning** for surprising or destructive behavior.
- **Update a shared reference file** if it was incomplete or wrong.
- **Add a permission entry** for a frequently-used safe command.
- **Propose a new script or skill** when a pattern recurs.

**For obvious, low-risk improvements** (a Common Mistakes entry, a permission for a
frequently-used safe command, a small syntax fix) go ahead and make the change -
present it as "Applied" rather than "Proposed".

**For larger changes** (new scripts, new skills, significant skill rewrites),
present the proposal with a clear before/after and wait for user approval.

### 6. Apply approved fixes

After the user selects which proposals to implement, apply the changes.

## Common Mistakes

- **Run the parser with `npx tsx`, not `pnpm run script`** - there is no wired
  `script` runner here; invoke `npx tsx <path>` directly against the bundled
  `parse-session.ts`.
- **`import.meta.main` is Bun-only** - tsx/Node don't support it. If the parser produces zero output, this is likely why.
- **Don't be overly specific** - a fix for "when curling emojidb.org, escape XML in plist" is too narrow. A fix for "when writing inline scripts in plist XML, remember to escape `<` and `>`" is general enough.
