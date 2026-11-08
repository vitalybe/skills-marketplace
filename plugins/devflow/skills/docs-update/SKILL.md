---
name: docs-update
description: Update or create documentation in the appropriate location (patterns, architecture, feature docs, or CLAUDE.md files). Keeps CLAUDE.md short and splits docs into sub-pages as they grow
---

# Documentation Update Skill

Create or update project documentation.

## Phase 1: Classify

Use the skill arguments if given; ask only what you need to pin down the type
and scope. Type is one of: Pattern | Architecture | Feature | Developer
Guideline | Agent Instruction | Skill.

- **Feature**: how a specific capability behaves (a menu, a marker contract, a
  gate, an import step). It describes the system, so it belongs in a doc (see
  Phase 2 for when CLAUDE.md may hold it instead). Use the Architecture style,
  scaled down.
- **Agent Instruction**: how an agent should *work* in the project (commands,
  ports, conventions, do/don't). It is not a description of how the system
  behaves - that is Architecture or Feature.

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

Scope it (one module/service vs cross-cutting), then run `wc -l` on the
CLAUDE.md that applies and on the candidate target doc. Place the content by
these rules, applied to each CLAUDE.md separately (repo root and each app). If
the project documents its own layout (e.g. `_team_docs/`), follow that;
otherwise use a `docs/` folder next to that CLAUDE.md.

**CLAUDE.md** is the orientation file: stack, ports, project structure,
commands, conventions, and an index of the docs. It may also hold the initial
project details directly, and in a small project (under the limit below) short
Feature or Architecture notes may live there too.

**Docs** hold the substance: Architecture, Pattern and Feature content. A doc
is a real topic, not a note: never create a doc for a one-liner. Put a small
addition in the closest existing doc; if none fits, in a broader topic doc
(e.g. `docs/ui.md`) rather than a narrow new one.

**Growth is organic.** The numbers are guides, not hard limits; don't split a
file that still reads well.

- **CLAUDE.md over ~150 lines**: new substance goes to a doc, not CLAUDE.md.
  Move out the sections this change touches, then the largest self-contained
  topics (each ~30+ lines) as `docs/<topic>.md`, until CLAUDE.md is down to
  ~100 lines, leaving one index line per doc. If that means moving more than
  ~3 sections, move only the touched ones and propose a separate cleanup task
  for the rest; never migrate a huge file inside a feature task.
- **A doc over ~300 lines and covering distinct subtopics**: turn it into a
  folder, `docs/<topic>/README.md` as the overview with a link per sub-page,
  and one sub-page per subtopic, each ~30+ lines. The parent stays an overview,
  not a dump.

State the proposed layout (new files, moved sections) and confirm the target
paths with the user; when running non-interactively, state it in the summary
instead. A split moves text and relinks it; it does not rewrite it.

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

**Feature:** the Architecture style, scaled down: bullets, flows and rules of
the capability, a Key Components table only if it helps. No full template
needed.

**CLAUDE.md:** add to the right section, match the existing format, be brief.
Only orientation content and index lines go here (see Phase 2).

**Diagrams:** follow the diagram rules in
`_devflow-shared/docs/plan-format.md`, plus: a diagram **replaces** the
prose it describes, never supplements it; a 1-line ASCII flow (`A → B → C`) is
fine for trivial cases; when updating an existing doc, migrate qualifying prose
blocks to mermaid and leave existing short ASCII alone.

Show the draft to the user and iterate.

## Phase 5: Update References

Keep the docs index in CLAUDE.md complete: one bullet, one sentence per
top-level doc, naming key topics (tables, classes) and when to read it ("read
before changing X"). Sub-pages of a split doc
are linked from that doc's README, not from CLAUDE.md, so the index stays
short. Show every CLAUDE.md change for approval.

## Phase 6: Finalize

Show the full diff. Verify markdown formatting and that all paths and
references resolve. For every moved or split file and section, `rg` the repo
(other docs, `_plans/`, skills) for links and anchors to it and fix them.
