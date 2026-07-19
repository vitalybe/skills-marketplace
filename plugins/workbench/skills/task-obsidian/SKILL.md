---
name: task-obsidian
description: >-
  Lists, opens, and creates personal tasks stored as frontmatter-tagged
  markdown files in the user's Obsidian vault, using the `obsidian-tasks`
  CLI (a Python single-file script installed at `~/hq/bin/obsidian-tasks`,
  callable from anywhere). Use this whenever the user asks about their
  personal tasks / to-dos / "what's on my list" / "what am I working on" /
  "add a task" — anything that lives in the Obsidian vault rather than in
  JIRA. Auto-triggers on phrases like "my tasks", "my todos", "my to-do
  list", "obsidian task", "vault task", "add to my list", "what should I
  do next", and on short-ID mentions matching `\d{6}(-[a-z0-9]+)?` when
  context makes clear it's a personal task. Distinct from `/workbench:task-jira`,
  which handles work tickets (AIE-NNN / DRV-NNN).
---

# Obsidian tasks via `obsidian-tasks`

A small Python CLI that treats markdown files in the Obsidian vault as
tasks. Files are detected by `task_is_active: "1"` in their YAML
frontmatter. Each task gets a short, stable ID printed in the listing.

## Locate the script

Run this once at the start of any obsidian-task-flavoured turn to know
which path to invoke; cache it for the rest of the turn:

```bash
OT=$(command -v obsidian-tasks || ls "$HOME/hq/bin/obsidian-tasks" 2>/dev/null)
[ -n "$OT" ] || echo "obsidian-tasks not installed - it lives in ~/hq/bin/"
```

For the rest of this doc, just write `obsidian-tasks` - substitute `$OT`
if it isn't on PATH.

The vault root is taken from `$OBSIDIAN_VAULT` (default
`~/obsidian`). Task files live under `data/tasks/data/`.

## Subcommand cheat sheet

```
obsidian-tasks list [--sort {modified,created,priority}]
                    [--tag TAG]... [--tag-no-children]
                    [--status STATUS]... [--all] [--limit N] [--json]
                                                  # ls is an alias for list
obsidian-tasks add [--priority {1,2,3}] [--status STATUS]
                   [--tag TAG]... [--body BODY] [--edit] [--print-path]
                   TITLE...                       # create a new task file
obsidian-tasks open ID [--editor EDITOR]          # open in Cursor (default)
obsidian-tasks path ID                            # print absolute file path
obsidian-tasks --help
```

`ID` is the short ID column from `list` (e.g. `260527-w`, `260518-hmr`).
IDs are stable across runs - safe to reference by ID in follow-ups.

`--tag` accepts the full tag (e.g. `work/drivenets/hr-mcp`). By default
it matches the tag and any children; `--tag-no-children` restricts to an
exact match. Multiple `--tag` flags OR together. Multiple `--status`
flags OR together.

Default `list` hides `done` tasks - pass `--all` to include them.

## Worked examples

### Show the active list

```bash
# Default: active tasks, sorted by modified desc
obsidian-tasks list

# Top of mind by priority (3 = high)
obsidian-tasks list --sort priority --limit 10

# Filter by tag - matches work/drivenets and any child like work/drivenets/hr-mcp
obsidian-tasks list --tag work/drivenets

# Exact tag, no children
obsidian-tasks list --tag personal --tag-no-children

# Multiple statuses
obsidian-tasks list --status open --status in-progress
```

### Read a specific task

```bash
# Resolve ID -> path, then cat / open
obsidian-tasks path 260518-hmr
cat "$(obsidian-tasks path 260518-hmr)"

# Open in editor (Cursor by default)
obsidian-tasks open 260518-hmr
```

### Add a task

**Always check for duplicates first.** Before calling `obsidian-tasks
add`, list existing active tasks and look for a fuzzy title match. If
the user has hinted at a tag, scope the search; otherwise scan
everything active.

```bash
# Tag-scoped: pull the active list under the same tag and eyeball
obsidian-tasks list --tag personal --limit 50

# Or grep the JSON for distinctive words from the proposed title
obsidian-tasks list --json --all --limit 200 \
  | jq -r 'select(.title | test("water filter"; "i")) | "\(.id)\t\(.status)\t\(.title)"'
```

If anything plausible comes back, **stop and show it to the user**
("260519 is already 'Order water filter' - open that instead?"). Only
proceed to `obsidian-tasks add` once the user confirms it's a new item
or the search is empty. Done tasks (`--all` to include them) also
warrant a mention - the user may want to reopen rather than re-add.

```bash
# Bare title (multi-word OK, no quoting needed)
obsidian-tasks add Order water filter

# With tag(s) and priority
obsidian-tasks add --tag personal --priority 3 Pay rent before the 1st

# Work task under a nested tag
obsidian-tasks add --tag work/drivenets/hr-mcp HR MCP - add resume keyword search

# With initial body and open in editor right away
obsidian-tasks add --tag personal --body "groceries, dry cleaner" Errands --edit

# Get just the path back (scripting)
NEW=$(obsidian-tasks add --tag personal --print-path Buy birthday card)
```

### Use JSON for downstream processing

```bash
# Newline-delimited JSON, one task per line
obsidian-tasks list --json --tag work/drivenets --limit 20 \
  | jq -r 'select(.priority >= 2) | "\(.id)\t\(.title)"'
```

JSON fields include `id`, `path`, `rel_path`, `title`, `status`,
`priority` (int), `priority_raw`, `tags` (array), `created`, `modified`.

## When to use this vs `/workbench:task-jira`

- **Personal life, hobbies, errands, household, family** → here.
- **DriveNets / AIE / DRV tickets, sprints, status transitions** →
  `/workbench:task-jira`.
- A vault task tagged `work/...` is still a personal note about work, not
  a JIRA ticket - use this skill. Reach for `/workbench:task-jira` only when the
  user mentions a real KEY or asks about JIRA explicitly.

If a request is ambiguous ("what should I work on today?"), check both:
list the top of the obsidian active list AND the user's open JIRA
issues, then let the user pick.

## Pitfalls

- The default sort is `modified` desc, not priority. If the user asks
  "what's most important", pass `--sort priority`.
- `--tag` is a substring on tag paths only when children are allowed -
  e.g. `--tag work` matches `work/drivenets/hr-mcp`. Use
  `--tag-no-children` if you want to exclude child tags.
- `add` writes the file immediately - there's no dry-run flag. For long
  bodies, prefer `--edit` (opens in `$EDITOR`) over `--body "…"` so the
  user reviews before saving.
- Short IDs (e.g. `260519`) look like dates but are not - don't try to
  parse them. Always resolve through `path` / `open`.
- The script is a `uv run` shebang - first call may install `pyyaml` and
  print a one-time `uv` setup line on stderr. Ignore.
