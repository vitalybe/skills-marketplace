---
name: docs-update
description: Update or create documentation in the appropriate location (patterns, architecture, or CLAUDE.md files)
---

# Documentation Update Skill

Create or update project documentation.

## Phase 1: Classify

Use the skill arguments if given; ask only what you need to pin down the type
and scope. Type is one of: Pattern | Architecture | Developer Guideline |
Agent Instruction | Skill.

**Doc or skill?** Make it a **skill** when the content is an actionable
workflow or CLI recipe Claude should execute, is only relevant sometimes (so it
shouldn't burn context every conversation), or benefits from dynamic context.
Keep it a **doc** when it is foundational, passive reference needed broadly -
architecture, patterns, conventions.

If it's a skill, write a `SKILL.md` with `name`, `description` (when to
auto-invoke), and optional `argument-hint`; put the CLI references and
workflow in the body; inject dynamic context where it helps; extract shared
agent instructions to a docs location and reference them; point CLAUDE.md at
the skill. Then jump to Phase 6.

## Phase 2: Determine Location

Scope it (one module/service vs cross-cutting), then follow the project's
documentation conventions - check CLAUDE.md for the existing organization.
Confirm the target path with the user.

## Phase 3: Explore Existing Content

Use the Explore agent to read the current file (if updating), find similar
docs for format consistency, and locate the CLAUDE.md references to touch.
If the content already exists somewhere, reference that doc instead of
duplicating it.

## Phase 4: Draft Content

**Developer Guidelines:** one concise, actionable rule in the right section of
the project's guidelines file, matching the format of existing entries.

**Patterns:** practical, with anonymized code (`<ComponentContainer />`,
`fetchData()`) and checkmark/cross comparisons.

```
# [Pattern Name]
[1-2 sentence description]

## Structure
[How it's organized]

## Example
[Anonymized code showing pattern usage]

## Usage
[When to use, best practices, checkmark/cross examples]
```

**Architecture:** dense technical spec, assume expertise, focused on flows,
pipelines, and data models. Split high-level from low-level.

```
# [System Name]
[1 sentence description]

## High-Level Overview
### [Core Concept/Architecture Name]
[1-2 sentences on the pattern] + **Key aspect**: bullets

### [Data Flow / Lifecycle Summary]
[Diagram or bullet summary of the flow]

## Low-Level Details
### [Mechanism/Component Name]
[How it works - rules, patterns, behavior] + **Key rule:** bullets

### Key Components
| File | Purpose |
|------|---------|
| `file.ts` | Brief description |

## Related Documentation
- [Other Doc](./other-doc.md) - Brief description of relationship
```

Architecture style: bullets not paragraphs; **bold** for table/class names and
key terms, `code` for literal values, keys, and paths; jargon over layman
terms. Document the system's own mechanisms and how components interact - not
downstream usage of its output, individual fields, constants, props, or config
values. For UI, that means logic flows (scrolling, pagination, gestures), not
component props. No code examples, no SQL/DDL (mermaid is exempt), no
tutorials. Cross-reference instead of duplicating; if more detail is wanted,
the user will ask.

**CLAUDE.md:** add to the right section, match the existing format, be brief.

**Diagrams:** follow the diagram rules in
`${CLAUDE_PLUGIN_ROOT}/docs/plan-format.md`, plus: a diagram **replaces** the
prose it describes, never supplements it; a 1-line ASCII flow (`A → B → C`) is
fine for trivial cases; when updating an existing doc, migrate qualifying prose
blocks to mermaid and leave existing short ASCII alone.

Show the draft to the user and iterate.

## Phase 5: Update References

If a new pattern/architecture doc was created, reference it from the relevant
CLAUDE.md file(s) - one bullet, one sentence, naming key topics (tables,
classes). Show every CLAUDE.md change for approval.

## Phase 6: Finalize

Show the full diff. Verify markdown formatting and that all paths and
references resolve.
