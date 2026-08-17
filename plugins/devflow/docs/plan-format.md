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

Get the plan path for a task (KEY is auto-derived from the current branch
when omitted; safe both for creating a new plan and reading one mid-flight):

```bash
tasks plan [KEY] [TITLE]
```

> **`_plans/` must NOT be gitignored.** The whole model here is a
> versioned, diffable plan that ships with the PR and stays on `main` as a
> permanent record - a `.gitignore` entry for `_plans/` defeats that. If a
> "commit the plan file" step fails with *"paths are ignored by one of your
> .gitignore files"*, treat it as a **repo misconfiguration**: surface it to
> the user and offer to remove the `_plans/` line from `.gitignore` - do not
> paper over it with `git add -f` or silently downgrade the plan to a
> throwaway local file.

## Structure

One H1 (the task summary), then sections as the flow progresses:

```markdown
# <Task summary>

## Requirements Brief
(1-2 sentences: what we want and why)

## Design                 (optional)
(the Claude Design link + the key UX/UI decisions taken)

## Plan

### 1. Task Scope
(1-2 sentences: what this task covers)

### 2. Key Changes Summary
(1-2 paragraphs of prose condensing the whole plan)

### 3. Main Changes
#### UI and UX Flows      (optional)
#### Storage Changes      (optional)
#### API Changes          (optional)

### 4. Testing Strategy
(3-5 lines: what gets verified, at what level)

### 5. Detailed Implementation
(the buildable detail - files, contracts, cases, diagrams)

## Plan Review Findings
(decisions taken on plan-review findings)

## Code Review Findings
(decisions taken on code-review findings)

## Tests
(thin rollup - one line per test file)

## Acceptance
(acceptance criteria)

## Requirements
(full requirements Q&A - reference material)
```

`## Design` is created by the design phase when the task has UX/UI scope,
and the two review-findings sections by the review steps, only when there is
something to record; every other heading above is required.

Reader-first ordering: the brief orients at the top, so the plan reads
immediately after it; the full requirements are reference and sit at
the bottom.

## Plan format

What goes inside `## Plan`, and how `## Tests` relates to it. This is
the authoritative format spec. Testing is layered through the plan at three
zoom levels: strategy (`4. Testing Strategy`) → per-concern cases
(`5. Detailed Implementation`) → rollup index (`## Tests`).

### 1. Task Scope (1-2 sentences)

- What this task covers
- Reference to parent if applicable: "See Parent [ISSUE-KEY] for full UX flows"

### 2. Key Changes Summary

An expanded Task Scope: 1-2 paragraphs of prose that condense the entire
plan, logic and UI together. Cover the UX flow and the UI changes, the
architecture at event level (what happens when the user presses the button,
and what happens next when there is no button), and the data-storage
changes - all at a high level.

No implementation detail here, and no bullet lists of interfaces. A reader
who stops after this section should know what the change does and roughly
how it works.

### 3. Main Changes

The big visible changes, one subsection per area. All subsections are
optional: include only the ones the change actually touches, and for the
rest add a one-line bullet directly under Main Changes ("No UI changes",
"No storage changes").

- **#### UI and UX Flows** - how the UI and the UX flows change.
- **#### Storage Changes** - database, files, cookies, anything persisted -
  especially what may need a migration or has long-term effects.
- **#### API Changes** - endpoint additions, signature and contract changes.

### 4. Testing Strategy

3-5 lines: which capabilities get verified and at what level (unit /
integration / e2e / manual), plus anything deliberately *not* tested and
why. This is the top zoom level of the test plan - case detail appears
inline in Detailed Implementation, not here.

### 5. Detailed Implementation

Open with an **architecture flow** `flowchart` when the change introduces
multiple components that interact end-to-end (components + data flow, no
time axis). Skip for single-component edits.

- **Shared Data Interfaces** - the types, schemas, and payloads that cross
  module boundaries. Include only when interfaces affect multiple parts of
  the codebase.
- **Code flow** - 5-10 bullets from user action → data layer → render.
  Generic names, no full code.
- **Code Map** - optional. One mermaid diagram that graphs the *structure of
  the change*, placed below the architecture flow and just before the Files
  tree. Include it only when it genuinely clarifies the change, and pick
  **one** of the two forms - never both:
    1. **Concern ladder** (`flowchart TB`) - one node per concern group,
       ordered top-to-bottom by implementation order, each edge labeled with
       *why* that order exists ("guards", "persists via", "supersedes"). Nodes
       with no incoming edge are independent tracks that build in parallel. Node
       label = its 🟢🟡🔴 marker(s) first, then the bolded concern name, then a
       few headline files on the next line - e.g.
       `cfg["🟡 <b>Config</b><br/>.env.schema, env.d.ts"]`.
    2. **Contract map** (`classDiagram`) - the new/changed public contracts
       with their key signatures, and labeled edges for which contract calls
       or is consumed by which; use `<<stereotypes>>` for add/modify/rewrite
       status.

  Pick the ladder when build order is the hard part, the contract map when
  the shape of the new API is. Two rules, both learned from a failed
  module-dependency map:
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
  Code Map - don't restate it.

**Diagram rules:**

- `flowchart` for static shape. Use a `sequenceDiagram` only when the call
  shape is non-obvious from the prose - several components calling each other
  in a specific order that a reader can't infer. Otherwise skip it.
- ≤5 participants per `sequenceDiagram`. If more, split by phase
  (preferred when there's a natural temporal break) or abstract internal
  helpers into one participant. (The Code Map's own cap is ~12 nodes.)
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

## Review findings sections

`## Plan Review Findings` and `## Code Review Findings` are the durable
record of what the reviews turned up and what the user decided about it.
The review steps write **only decision-needed findings** here - findings the
agent already fixed itself go in the chat report and never into the plan.

Each section has two subsections:

- `### User decisions` - one entry per finding with the decision the user
  took: fixed as requested / rejected, with the reason / question asked,
  with the answer.
- `### Unhandled` - findings the user ignored or skipped past (e.g. said
  "go to the next phase" without addressing them).

## Lifecycle

- **Requirements phase** creates the file (scaffold, `## Requirements
  Brief` up top, full `## Requirements` at the bottom). If a plan file
  already exists for the task, update it in place.
- **Design phase** (UX/UI work only) writes `## Design` - the Claude Design
  link and the key UX/UI decisions.
- **Plan phase** fills in `## Plan` (all five subsections), `## Tests`,
  `## Acceptance`.
- **Plan review** appends to `## Plan Review Findings`.
- **Code phase** reads the file to drive implementation; may edit it if
  the plan changes during implementation (including recording tests
  discovered mid-implementation in their concern group + the rollup).
- **Code review** appends to `## Code Review Findings`.
- **Close phase** does **not** touch the file - it merges as-is.

After merge, the plan stays in `_plans/` on `main` as a permanent record.
