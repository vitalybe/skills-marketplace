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
- task name - optionally an Obsidian `[[wiki-link|Name]]` to a per-task subpage
- `(branch-or-slug, PR #NNN)` when applicable
- ` - ` then a short current status (e.g. "running", "code-review",
  "merged; <one-line what/why>")

```markdown
## Tasks

### Orchestrator

- [ ] [[AIE - Orchestrator - Rewind a session|Rewind a session]] (orchestrator-rewind-session, PR #237) - code-review
- [x] [[AIE - Orchestrator - Mock scenario dropdown|Mock scenario dropdown]] (orchestrator-mock-scenario-dropdown, PR #242) - merged; rebased onto main, unit 108 + e2e 5 green

### Tooling

- [x] Stop tracking varlock-generated `env.d.ts` (gitignore-varlock-env-dts, PR #240) - merged
```

## Conventions

- Group by `### <Project>` in both sections.
- One line per task; keep the status short. Extra details go to subpage.
- Active/recent items near the top of their group.
- Reference external plan files by absolute path as `[[external:<abs-path>]]`.
- Current-state voice: describe how things are now, no "was X now Y" history.
- The doc is the human-facing source of truth - keep it matching reality.
