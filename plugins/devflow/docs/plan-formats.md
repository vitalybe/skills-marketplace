# Plan files

Each task gets one living plan file under `_plans/`, committed on its
feature branch and merged with the PR. The issue tracker holds status +
phase + workflow metadata; the file holds the prose.

## Location & naming

```
_plans/<KEY>-<slug>.md    # task mode
_plans/<slug>.md          # task-less mode (no tracker key)
```

- `<KEY>`: the task tracker key (e.g. `AIE-2342`, `DRV-189`). Identifies the file.
- `<slug>`: kebab-case of the task summary, truncated to ~50 chars.
- Task-less runs have no KEY; the slug alone identifies the file.

Get the plan path for a task:

```bash
tasks plan [KEY] [TITLE]
```

`<KEY>` is the identity; `<slug>` is decorative. KEY is auto-derived
from the current branch when omitted. See **Resolution order** below
for the lookup behavior.

## Structure

One H1 (the task summary), then sections as the flow progresses:

```markdown
# <Task summary>

## Requirements Brief
(1-2 sentences: what we want and why)

## Plan
(the implementation plan - see **Plan format** below)

## Tests
(thin rollup - see **Plan format** below)

## Acceptance
(acceptance criteria)

## Requirements
(full requirements Q&A - reference material)
```

Additional sections are allowed; the five headings above are the
required ones.

Reader-first ordering: the brief orients at the top, so the plan reads
immediately after it; the full requirements are reference and sit at
the bottom.

## Plan format

What goes inside `## Plan`, and how `## Tests` relates to it. This is
the authoritative format spec. Testing is layered through the plan at three zoom
levels: strategy (Key Changes Summary) → per-concern cases (Detailed
Implementation) → rollup index (`## Tests`).

### 1. Task Scope (1-2 sentences)

- What this task covers
- Reference to parent if applicable: "See Parent [ISSUE-KEY] for full UX flows"

### 2. Key Changes Summary

- **UI changes and UX flows** - concise, high-level
- **Code Interface & Function Changes** - description-level (e.g., "Add X parameter to Y")
- **Shared Data Interfaces** - only if interfaces affect multiple parts of the codebase
- **Testing strategy** - 3-5 lines: which capabilities get verified and
  at what level (unit / integration / e2e / manual), plus anything
  deliberately *not* tested and why. This is the top zoom level of the
  test plan - case detail appears inline further down, not here.

### 3. Detailed Implementation

Open with an **architecture flow** diagram when the change introduces
multiple components that interact end-to-end. Use mermaid `flowchart`
for static shape (components + data flow, no time axis); use
`sequenceDiagram` when the change is itself a flow. Skip for
single-component edits.

- **Code flow** - 5-10 bullets from user action → data layer → render.
  Generic names, no full code. Replace with a `sequenceDiagram` when ≥3
  components call each other in a specific order.
- **Code Map** - one or two mermaid diagrams that graph the *structure of
  the change* (build order + contracts), placed below the architecture
  flow and just before the Files tree. They visualize what the prose in
  Changes by concern and Interfaces & Functions holds, so they must carry
  information those sections don't:
    1. **Concern ladder** (`flowchart TB`) - one node per concern group,
       ordered top-to-bottom by implementation order, each edge labeled with
       *why* that order exists ("guards", "persists via", "supersedes"). Nodes
       with no incoming edge are independent tracks that build in parallel. Node
       label = its 🟢🟡🔴 marker(s) first, then the bolded concern name, then a
       few headline files on the next line - e.g.
       `cfg["🟡 <b>Config</b><br/>.env.schema, env.d.ts"]`. Include when the
       plan has ≥3 concern groups.
    2. **Contract map** (`classDiagram`) - the new/changed public contracts
       with their key signatures, and labeled edges for which contract calls
       or is consumed by which; use `<<stereotypes>>` for add/modify/rewrite
       status. Include when the plan introduces or reshapes ≥4 public
       contracts. Skip for refactor- or config-only plans.

  Two rules, both learned from a failed module-dependency map:
    - **Every edge carries a reason a reader couldn't guess** ("guards",
      "supersedes", "runner delegates turns to"). If the only honest label
      is "imports", drop the edge.
    - **Nodes are concern groups or contracts, never bare files.** Files
      appear only inside node labels as headline examples; the Files tree
      stays the exhaustive inventory. Cap ~12 nodes / ~12 edges per diagram
      - collapse groups rather than exceed it.
- **End-to-end tests** - include when the change has a user-facing lifecycle
  worth driving through the real UI. Describe the harness (what's real vs.
  faked - external agents, paid APIs, and push/deploy operations get mocked
  at a seam, everything else runs for real; a test-mode auth bypass; a temp
  DB / data dir per run), then list the flows covered in general terms - one
  bullet per scenario, user action → what the UI should show. Name the tool
  (Playwright / Cypress / …) and where the fixtures live. Skip for changes
  with no UI lifecycle (libraries, pure backend, docs).
- **Files** - present in two passes:
    1. **Folder tree** in a fenced code block, showing every touched path.
       Format: indented folder structure with one file per line; after each
       filename, pad with spaces to a consistent column, then the status
       emoji, then a ≤6-word inline note describing the change. Include the
       legend below the tree.
    2. **Changes by concern** - group bullets by *kind of change* (e.g.
       "Doc reorganization", "Build & packaging", "Backend wiring",
       "Deletions", "Tests infrastructure"), not by folder. Each file
       appears once in the tree and once in exactly one concern group.
       Order concern groups by sensible implementation order - renames
       before consumers, deletions last.

       **Each concern group ends with a `Tests:` sub-bullet**: the test
       file(s) covering that concern plus 2-5 case-level bullets (happy
       path + key edge cases). Tests live next to the change they cover -
       this is the bottom zoom level of the test plan. A concern with no
       tests states `Tests: none - <why>`.

    Use these markers consistently: 🟢 Add · 🟡 Modify · 🔴 Remove. For
    renamed files, use 🟡 and note "renamed from X" in the inline note.
    For deleted directories, list the directory itself with 🔴 after its
    last deleted child. Example:

    ```
    apps/pcb-reviewer/src/backend/
      grouper/
        types.ts                    🟢 Zod schemas for grouper output + group slice
        grouper.ts                  🟢 Orchestrator: parallel per-page AI sessions
        grouperAgent.ts             🟢 Single-page agent: OpenAI Agent setup + tools
        groupSlicer.ts              🟢 3-hop closure slicer: groups → per-group data
        grouperValidator.ts         🟢 Post-session validation (hallucination guard)
        prompts/
          AGENT.md                  🟢 System prompt for grouper agent
          grouping_kb.md            🟢 Hardware domain knowledge base
      pipeline/
        preProcessingPipeline.ts    🟡 Add page slicing + grouper steps
    ```

- **Interfaces & Functions** - bullet/pseudo-code format, but full
  detail (props, key behaviors, "Displayed content") only for **new or
  changed public contracts**. Internal wiring is already covered by the
  Code Map - don't restate it. Add a small `sequenceDiagram` when
  several new classes/interfaces call each other and the call shape
  isn't obvious from the bullet list.

**Diagram rules:**

- ≤5 participants per `sequenceDiagram`. If more, split by phase
  (preferred when there's a natural temporal break) or abstract internal
  helpers into one participant. (The Code Map's own cap is ~12 nodes.)
- `sequenceDiagram` for ordered call flows (≥3 components, specific
  order). `flowchart` for static shape.
- Orient flowcharts top-to-bottom (portrait mode) - use `flowchart TB`
  (or `TD`), not `LR`. Portrait reads better in GitHub's narrow content
  column.
- Use mermaid fenced code blocks (```` ```mermaid ````) - GitHub renders
  them natively.
- Don't force a diagram. Rule lists, schemas, status codes, error
  semantics, single-component behavior - keep as prose.

### `## Tests` - the rollup

The plan file's `## Tests` section is a thin index, not a spec: one
line per test file, pointing at the concern group that specifies its
cases. It's the checklist a test run works from. No case-level detail - if
you're writing cases in the rollup, they belong inline in a concern
group instead.

```markdown
## Tests

- `grouper.test.ts` → Backend wiring
- `groupSlicer.test.ts` → Backend wiring
- `Toolbar.test.tsx` → UI
```

### Planning principles

- Data minimalism: store IDs, compute derived data at point of use
- Don't invent behavior: only add what's explicitly required
- Use existing structures: don't create new utility files when an existing class fits
- Purge dropped decisions: remove all references to anything decided against

## Lifecycle

- **Requirements phase** creates the file (scaffold, `## Requirements
  Brief` up top, full `## Requirements` at the bottom).
- **Plan phase** fills in `## Plan`, `## Tests`, `## Acceptance`.
- **Code phase** reads the file to drive implementation; may edit it if
  the plan changes during implementation (including recording tests
  discovered mid-implementation in their concern group + the rollup).
- **Close phase** does **not** touch the file - it merges as-is.

After merge, the plan stays in `_plans/` on `main` as a permanent record.

## Resolution order

`tasks plan` returns the first hit, falling through on miss:

1. **Current worktree.** Glob `_plans/<KEY>-*.md`. If exactly one matches,
   return it. (Multiple matches → `[[Error: ...]]`.)
2. **Other branch.** Find a local/remote branch ending with `-<KEY>`. If
   exactly one matches and it has a plan file, `git show` it into
   `/tmp/plan-<KEY>-PID.md` and return that path. (Used for cross-task
   reads, e.g. a child referencing its parent's plan.)
3. **Generate.** Otherwise echo the canonical path the script would
   create: `_plans/<KEY>-<slug>.md`, deriving the title from the
   tracker if `[TITLE]` wasn't passed.

**Task-less mode:** when no KEY resolves (no argument, branch doesn't
match a key pattern), `tasks plan` falls back to `_plans/<slug>.md`,
deriving the slug from `[TITLE]` if passed, else from the branch name.

So `tasks plan <KEY>` is safe to use both when creating a new plan and
when reading one mid-flight - no `if-exists` branching at the caller.

Temporary files in `/tmp` older than an hour are cleaned up on the next
call.

## Don't put plans in issue descriptions

The issue description holds the *task summary* only. The plan file is
the source of truth - it's versioned, diffable, visible in PRs, and
survives tracker migrations.
