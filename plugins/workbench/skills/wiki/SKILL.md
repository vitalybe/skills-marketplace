---
name: wiki
description: >-
  Read from and write to the user's personal Obsidian knowledge vault at
  `$OBSIDIAN_VAULT` (default `~/homebot/obsidian`) - wiki pages, contacts,
  calendar events, finance/receipts, kids-money, "tell someone" items,
  day logs, movies, storage, and other structured data tables. Use
  whenever the user wants to capture, look up, route, or update personal
  knowledge in their vault: "add this to my wiki/notes", "save this
  link", "remember that...", "note that...", "log this", "what do my
  notes say about X", "look up X in my vault", "add a contact", "create a
  calendar event", "tell P / tell someone about X", "journal this",
  receipts / bank exports / manual payments, or any free-form note that
  belongs in the vault. Also lists, opens, and creates personal tasks
  (plain `- [ ]` lines in notes): "my tasks", "my todos", "my to-do
  list", "what's on my list", "what am I working on", "what should I do
  next", "add a task", "add to my list", "obsidian task", "vault task".
  The vault's own `CLAUDE.md` is the routing source-of-truth; this
  skill just sends you there. Distinct from `/workbench:task-jira`
  (work tickets) - reach for that when the input is a JIRA ticket.
---

# Obsidian wiki/vault routing

The user keeps a personal knowledge vault (notes, contacts, finance,
structured data tables, day logs, "tell someone" queue, etc.) as
markdown files. This skill is a thin entry point: **all the real routing
and authoring rules live in the vault's own `CLAUDE.md`** - treat that
file as the source-of-truth and follow it exactly. Do not duplicate or
guess its rules here; read them fresh each time so they never drift.

## Start of every vault turn

1. Resolve the vault root from `$OBSIDIAN_VAULT` (default `~/homebot/obsidian`):

   ```bash
   VAULT="${OBSIDIAN_VAULT:-$HOME/homebot/obsidian}"
   [ -d "$VAULT" ] || echo "vault not found - set \$OBSIDIAN_VAULT"
   ```

2. **Read `$VAULT/CLAUDE.md` first.** It is the authoring playbook:
   routing rules, structured-page handlers, logging, frontmatter/YAML
   validity, wikilink conventions, and keeping `Index.md` / the Tags
   registry in sync.

3. Match the user's input to a destination per `CLAUDE.md`, then follow
   that destination's rules (a `structure.md` page is its own handler; a
   wiki page follows the `p-wiki-_pages` playbook; some routes call a
   named binary like `create-contact` or `create-calendar-event`).

The vault `CLAUDE.md` is authoritative for everything downstream -
routing via `Index.md`, `meta/people.md` / `meta/Tags.md`, YAML
frontmatter validity, session logging, attachments, and keeping
`Index.md` in sync. Follow it; don't restate its rules here.

## Writing: route directly by the vault's rules

Every write, including a new task, is placed by following the vault's
own routing docs in this session, not by ad-hoc logic. Read them fresh
from `$VAULT`:

- `CLAUDE.md` and `meta/docs/routing.md` - primary routes, host-page
  choice via `Index.md`, `meta/people.md`, `meta/Tags.md`.
- `meta/importers/FAN-OUT.md` - the six steps: host page, record, task
  lines (step 3), people, validate and log. Skip step 5 (archive and
  ledger).
- `meta/Task Format.md` and `meta/skills/p-route/SKILL.md` - task line
  format and the shared routing rules (never create a wiki page without
  asking; unplaceable content goes to an `areas/unrouted/` row).

A task never bypasses the Work Board rule: a DriveNets work task on
Vitaly goes to the `# Tasks` section of `areas/work/Work Board.md`,
under a `###` project heading, with the hard-match dedup rules of
FAN-OUT step 3.

Nothing is saved as a capture and nothing is archived, so there is no
router ledger line. When the run changed vault content, add one
activity-log line with `meta/scripts/vault-log --title wiki --summary
"<text>" --to '[[Page]]'`, and run
`meta/scripts/validate-obsidian-frontmatter <edited pages>` (0 errors).
Created or deleted wiki pages also update `Index.md`. Reply with what
was filed where. Reads and lookups stay direct.

## Personal tasks

Tasks are plain `- [ ]` lines in the notes that explain them. No task
database, no CLI: the list is computed with ripgrep each time. Format
reference: `$VAULT/meta/Task Format.md`.

**Find / list** (direct reads, run from `$VAULT`):

```bash
rg -n --no-heading '^\s*- \[ \] ' wiki/ shared/ -g '!_attachments/*'                  # all open
rg -n --no-heading '^\s*- \[ \] ' wiki/work/ -g '!_attachments/*'                     # work only
rg -n --no-heading '^\s*- \[ \] .*due:\d{4}-\d{2}-\d{2}' wiki/ -g '!_attachments/*'   # dated
rg -n -B5 -A5 'water filter' "wiki/personal/Home Tasks.md"                            # context
```

- `rg` prints `path:line:text`; the path is the context. Read the heading
  above a line: items under `## Someday` are not active.
- Also check `areas/work/Work Board.md` (`# Tasks`) for DriveNets work tasks.
- No task IDs; refer to `file:line` or path + title.
- Don't grep `data/` (ledger rows). A packing list or recipe uses `- [ ]`
  too: judge by the page, not the line.
- "What should I work on?" is ambiguous with JIRA: grep the vault and
  list open JIRA issues (`/workbench:task-jira`), let the user pick.

**Line format:** `- [ ] Title due:YYYY-MM-DD !` - `due:` only for a real
external deadline, `!` rare, sub-steps as nested checkboxes.

**Create:** dedup first (`rg -n -i '^\s*- \[[ x]\] .*<words>' wiki/ shared/
"areas/work/Work Board.md"`); if something plausible exists, show it to
the user instead of adding. Then place it per FAN-OUT step 3 and
`meta/Task Format.md`: a DriveNets work task on Vitaly goes to
`areas/work/Work Board.md` `# Tasks` under the matching `###` heading (a
new heading only if none fits), applying the Work Board hard-match
dedup; a personal task goes under `## Tasks` on the note it concerns,
else [[Home Tasks]]. Then log and validate as above.

**Close:** tick in place (`- [x]`), same page only; follow the vault
`CLAUDE.md` rules for the edit.

## When to use this vs `/workbench:task-jira`

- Knowledge, notes, links, contacts, personal tasks (including tasks on
  work pages) → here.
- A JIRA ticket (AIE-NNN, DRV-NNN, sprints, transitions) → `/workbench:task-jira`.
