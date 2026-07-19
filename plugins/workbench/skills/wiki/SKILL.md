---
name: wiki
description: >-
  Read from and write to the user's personal Obsidian knowledge vault at
  `$OBSIDIAN_VAULT` (default `~/obsidian`) - wiki pages, contacts,
  calendar events, finance/receipts, kids-money, "tell someone" items,
  day logs, movies, storage, and other structured data tables. Use
  whenever the user wants to capture, look up, route, or update personal
  knowledge in their vault: "add this to my wiki/notes", "save this
  link", "remember that...", "note that...", "log this", "what do my
  notes say about X", "look up X in my vault", "add a contact", "create a
  calendar event", "tell P / tell someone about X", "journal this",
  receipts / bank exports / manual payments, or any free-form note that
  belongs in the vault. The vault's own `CLAUDE.md` is the routing
  source-of-truth; this skill just sends you there. Distinct from
  `/workbench:task-obsidian` (personal to-dos / tasks) and `/workbench:task-jira` (work
  tickets) - reach for those when the input is an actionable task or a
  JIRA ticket rather than knowledge to file.
---

# Obsidian wiki/vault routing

The user keeps a personal knowledge vault (notes, contacts, finance,
structured data tables, day logs, "tell someone" queue, etc.) as
markdown files. This skill is a thin entry point: **all the real routing
and authoring rules live in the vault's own `CLAUDE.md`** - treat that
file as the source-of-truth and follow it exactly. Do not duplicate or
guess its rules here; read them fresh each time so they never drift.

## Start of every vault turn

1. Resolve the vault root from `$OBSIDIAN_VAULT` (default `~/obsidian`):

   ```bash
   VAULT="${OBSIDIAN_VAULT:-$HOME/obsidian}"
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
routing via `Index.md`, `meta/People.md` / `meta/Tags.md`, YAML
frontmatter validity, session logging, attachments, and keeping
`Index.md` in sync. Follow it; don't restate its rules here.

## When to use this vs the task skills

- Knowledge to file, a page to read/update, a note/link/contact/receipt
  to capture, something to "tell" a person → **here** (route via the
  vault `CLAUDE.md`).
- An actionable personal to-do ("add a task", "what's on my list") →
  `/workbench:task-obsidian`.
- A work ticket / JIRA issue (AIE-NNN, DRV-NNN, sprints, transitions) →
  `/workbench:task-jira`.

If a request mixes knowledge + a task (e.g. meeting notes that imply
follow-ups), the vault `CLAUDE.md` meeting route already covers it -
follow it (file the notes, then create task rows via
`data/tasks/structure.md`).
