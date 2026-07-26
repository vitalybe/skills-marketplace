# Status-doc format

The target is a single markdown file: live status of the orchestration work,
grouped by project. Structure, top to bottom:

## Optional header

If the doc lives in an Obsidian vault, an `> [!info] Parent` callout linking
its parent page. Skip otherwise.

```markdown
> [!info] Parent
> [[DriveNets]]
```

## Intro

One short paragraph: what the doc is (live status, grouped by project) and any
linking conventions in use (subpage naming, where plans live).

## `## Open questions`

Things needing the user's decision. Grouped by `### <Project>` headings.
Checkbox items (`- [ ]`), each a short description plus optional link(s).
Check off (`- [x]`) once decided.

```markdown
## Open questions

### Orchestrator

- [ ] **Deploy** manual infra - remaining: GHCR image push, nginx config drift. → [[AIE - Orchestrator - Deploy]]
```

## `## Tasks`

Grouped by `### <Project>` headings. One checkbox line per task:

- `- [ ]` in-flight / `- [x]` done
- a 🟡 prefix on items actively in progress, e.g. `- [ ] 🟡 **Name** - ...`
- task name in **bold** - optionally an Obsidian `[[tasks/<Name>|Name]]` link
  (wrapped in the bold) to a per-task subpage in the `tasks/` subfolder relative
  to this doc, used when the task carries extra detail
- `(branch-or-slug, PR #NNN)` when applicable
- ` - ` then a short current status (e.g. "running", "code-review",
  "merged; <one-line what/why>")

```markdown
## Tasks

### Orchestrator

- [ ] 🟡 **[[tasks/AIE - Orchestrator - Rewind a session|Rewind a session]]** (orchestrator-rewind-session, PR #237) - code-review
- [x] **[[tasks/AIE - Orchestrator - Mock scenario dropdown|Mock scenario dropdown]]** (orchestrator-mock-scenario-dropdown, PR #242) - merged; rebased onto main, unit 108 + e2e 5 green

### Tooling

- [x] **Stop tracking varlock-generated `env.d.ts`** (gitignore-varlock-env-dts, PR #240) - merged
```

## `## Pending tasks`

The drop box for work the user wants spawned. Present only when the pending-tasks
watcher is running (see [monitoring.md](monitoring.md)); the watcher parses this
section, so its format is a contract, not a style choice:

- An item is a **top-level `- [ ]` line** with a non-empty title, plus any
  following **indented** lines (sub-bullets, pasted images, detail) - together
  they are the item's block, and the whole block is handed to the dispatcher.
- `- [x]` and empty-title checkboxes are ignored.
- A **plain `- ` bullet is not an item** and will never fire. When the user writes
  one, say so rather than letting it sit there unspawned.

```markdown
## Pending tasks

- [ ] **Bottom nav pill mis-highlights a cased path** - `bottomNav.tsx:88` uses an
      exact-match lookup, so `/History` highlights Chat.
  - one-line `.toLowerCase()` fix
```

Items leave this section when they are dispatched: the block moves into
`## Tasks` as a normal task line. The doc is usually open in the user's editor
while they write here, so that move is always a narrow edit of the one block.

## Conventions

- Group by `### <Project>` in both sections.
- One line per task; keep the status short. Extra detail goes to a per-task
  subpage in the `tasks/` subfolder relative to this doc.
- Bold the task name; prefix actively in-progress tasks with 🟡.
- Prefix a task the orchestrator is auto-driving (per `/workbench:orchestrator-drive`)
  with 🚗 instead of 🟡, and note it in the status text, e.g.
  `- [ ] 🚗 **Name** - auto-driving; approved plan, in Code`. Drop the 🚗 back to
  🟡 (or 🟢/checked) once driving ends or the task reaches "ready to integrate".
- Active/recent items near the top of their group.
- Reference external plan files by absolute path as `[[external:<abs-path>]]`.
- Current-state voice: describe how things are now, no "was X now Y" history.
- The doc is the human-facing source of truth - keep it matching reality.
