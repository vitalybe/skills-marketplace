---
name: docs-update
description: Update or create documentation in the appropriate location (patterns, architecture, or CLAUDE.md files)
---

# Documentation Update Skill

Guides you through creating or updating project documentation.

## Workflow

### Phase 1: Gather Requirements

- If user provided arguments with skill invocation, use them to understand the request
- Only ask clarifying questions if needed to determine documentation type and scope
- **Classify type:** Pattern | Architecture | Developer Guideline | Agent Instruction | Skill

**Doc vs Skill decision:** Before proceeding, determine if the content should be a **skill** instead of a doc. Convert to a skill when:

- The content describes **actionable workflows or CLI commands** that Claude should execute
- It's only relevant **sometimes**, not every conversation (saves context window)
- The user would benefit from **invoking it explicitly** with `/skill-name`
- It would benefit from **dynamic context**

Keep as a doc when:

- It's **foundational reference** needed broadly across conversations (architecture, patterns, conventions)
- It's **passive knowledge** - Claude needs to understand it, not act on it

If classified as a skill, skip to Phase 2b.

### Phase 2b: Create Skill (if classified as Skill)

1. Create the skill SKILL.md with YAML frontmatter:
   - `name` - skill name (used as `/skill-name`)
   - `description` - when Claude should auto-invoke this skill
   - `argument-hint` - optional hint for expected arguments
2. Write the skill content with CLI references, workflows, and instructions
3. Use dynamic context injection where useful (e.g., current branch, live status)
4. For shared agent instructions, extract to a docs location and reference from the skill. Skill-specific phases should stay in the skill folder.
5. Update CLAUDE.md reference to point to the skill
6. Skip to Phase 6 (Finalize)

### Phase 2: Determine Location

**Step 1:** Determine project scope - is it specific to one module/service, or general/cross-cutting?

**Step 2:** Determine type and path - follow the project's documentation structure conventions. Check CLAUDE.md for existing doc organization.

Confirm target location with user.

### Phase 3: Explore Existing Content

Use Task tool (Explore agent) to:

- Read current content if updating existing file
- Find similar docs for format consistency
- Identify where CLAUDE.md references should be added

**Avoid duplication:** Before adding content, check if it already exists in existing docs. Reference existing docs instead of duplicating.

### Phase 4: Draft Content

**For Developer Guidelines:**

- Add to the appropriate section in the project's guidelines file
- Keep rules concise and actionable
- Match the format of existing entries

**For Patterns:**

Structure:

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

**For Architecture:**

Dense, technical specification format - assume expertise. **Focus on flows, pipelines, and data models.**

Split into **High-Level Overview** and **Low-Level Details**:

Structure:

```
# [System Name]

[1 sentence description]

## High-Level Overview

### [Core Concept/Architecture Name]

[1-2 sentences describing the pattern/approach]

- **Key aspect**: [Brief description]
- **Key aspect**: [Brief description]

### [Data Flow / Lifecycle Summary]

[Simple ASCII diagram or bullet summary of the flow]

---

## Low-Level Details

### [Mechanism/Component Name]

[How this component works - rules, patterns, behavior]

- **Key rule/pattern:** [Brief explanation]
- **Key rule/pattern:** [Brief explanation]

### Key Components

| File | Purpose |
|------|---------|
| `file.ts` | Brief description |

## Related Documentation

- [Other Doc](./other-doc.md) - Brief description of relationship
```

**Style Guidelines:**

- **Focus on the system itself:** Mechanisms, rules, validation patterns, how components interact
- **Avoid downstream usage:** Don't document what happens with the output unless it's core to understanding the system
- **Avoid field-level details:** Don't list individual fields unless they illustrate a key architectural concept
- **Avoid:** Constant values, prop explanations, configuration details, business logic details
- **For UI:** Document logic flows (scrolling, pagination, gestures) not component props
- Use **bold** for table names, class names, key terms, section labels
- Use `code` for literal values, keys, file paths
- Technical jargon over layman terms (e.g., "sparse persistence layer," "RLS for multi-tenant isolation")
- Bullet points, not paragraphs
- NO code examples, NO SQL/DDL schemas - describe conceptually. Mermaid blocks are exempt (see Diagrams below).
- NO tutorials or how-to details - reference only
- Condensed to essential concepts - keep it high-level
- Each section serves a specific architectural purpose
- **Cross-reference** related docs instead of duplicating content or explaining downstream usage
- **If details are needed, user will ask** - don't preemptively include exhaustive field lists

**Diagrams:**

- Prefer mermaid over prose when content describes ≥3 components calling each other in a specific order - **replace** the prose, don't supplement it.
- `sequenceDiagram` for ordered call flows. `flowchart` for static shape (components + data flow, no time axis).
- ≤5 participants per diagram. If more, split by phase (natural temporal break) or abstract internal helpers into one participant.
- Use mermaid fenced code blocks (```` ```mermaid ````) - GitHub renders them natively.
- Short 1-line ASCII (`A → B → C`) is fine for trivial cases; longer ASCII should become mermaid.
- Don't force a diagram for rule lists, schemas, status codes, error semantics, or single-component behavior.
- When updating an existing doc, migrate prose blocks that match the heuristic above to mermaid - existing short ASCII diagrams can stay.

**For CLAUDE.md:**

- Add to appropriate section
- Keep consistent with existing format
- Be concise

Show draft to user, iterate on feedback.

### Phase 5: Update References

If new pattern/architecture doc created, add reference to appropriate CLAUDE.md file(s).

**Format:** One bullet, one sentence, key topics (table names, classes, etc.)

Show all CLAUDE.md changes to user for approval.

### Phase 6: Finalize

- Show full diff to user
- Verify markdown formatting and file paths

## Guidelines

- Match format of existing docs
- For CLAUDE.md changes, always show full diff before committing
- Use anonymized examples in patterns (e.g., `<ComponentContainer />`, `fetchData()`)
- **Architecture docs:** Dense technical specs, no code examples, assume expertise
- **Pattern docs:** Practical with anonymized code examples and checkmark/cross comparisons
- Keep documentation concise and actionable
- Verify all paths and references are correct
