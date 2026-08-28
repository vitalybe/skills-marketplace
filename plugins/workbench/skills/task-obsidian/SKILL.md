---
name: task-obsidian
description: >-
  Lists, opens, and creates personal tasks in the user's Obsidian vault.
  Tasks are plain `- [ ]` checkbox lines living in the notes that explain
  them, found with ripgrep - there is no task database and no CLI. Use
  this whenever the user asks about their personal tasks / to-dos /
  "what's on my list" / "what am I working on" / "add a task" — anything
  that lives in the Obsidian vault rather than in JIRA. Auto-triggers on
  phrases like "my tasks", "my todos", "my to-do list", "obsidian task",
  "vault task", "add to my list", "what should I do next". Distinct from
  `/workbench:task-jira`, which handles work tickets (AIE-NNN / DRV-NNN).
---

# Obsidian tasks

Tasks live as `- [ ]` checkbox lines inside the notes that explain them.
There is no task table, no plugin, and no CLI - the list is computed by
grep every time you need it. Nothing stores it, so nothing can go stale.

The vault root is `$OBSIDIAN_VAULT` (default `~/homebot/obsidian`). The
authoritative description of the format lives in the vault at
`data/tasks/structure.md`; read it if anything below is ambiguous.

## Where a task lives

Three destinations, in this order of preference:

1. **The note that explains it**, under a `## Tasks` heading - a car's
   test on `Kia Niro`, a dashboard bug on `Drivenets - Cost Dashboard`.
   A task's context is not derivable; its flat list is.
2. **`wiki/personal/Home Tasks.md`** - a loose personal errand with no
   note of its own. It has `## Now`, `## Money`, `## Kids`, `## House`,
   `## Someday`, `## Done`.
3. **`wiki/work/drivenets/Work Tasks.md`** - a loose work item with no
   project note.

Never create a `misc` page, and never write under `data/tasks/` - that
folder is a frozen archive of the old system.

## Line format

```markdown
- [ ] Book Simba's quadrivalent vaccine - clinic 09-7745099
- [ ] Renew the Apple Developer Program membership due:2027-06-28 !
```

Title, then optional `due:YYYY-MM-DD`, then optional trailing `!` for
high priority. That is the whole schema.

- `due:` is a **real deadline imposed from outside** - the test expires,
  the bill accrues interest, the flight leaves. Never invent one to mean
  "I'd like to get to this by then"; once every date is overdue the
  marker stops carrying information.
- `!` is rare. Most tasks carry nothing.
- Sub-steps of one task are nested checkboxes under it.

## List

```bash
cd "$OBSIDIAN_VAULT"

# Everything open
rg -n --no-heading '^\s*- \[ \] ' wiki/ shared/ -g '!_attachments/*'

# Work only / personal only
rg -n --no-heading '^\s*- \[ \] ' wiki/work/ -g '!_attachments/*'
rg -n --no-heading '^\s*- \[ \] ' wiki/ shared/ -g '!_attachments/*' -g '!wiki/work/*'

# One topic
rg -n --no-heading '^\s*- \[ \] ' "wiki/personal/Home Tasks.md"

# Dated, soonest first
rg -n --no-heading '^\s*- \[ \] .*due:\d{4}-\d{2}-\d{2}' wiki/ -g '!_attachments/*' \
  | grep -o 'due:[0-9-]*.*' | sort
```

`rg` prints `path:line:text`. The **path is the context** - it tells you
which project or topic the task belongs to. Read the heading above the
line too: an item under `## Someday` is not on the active list.

There are no task IDs. Refer to a task by its path and title, or by
`file:line` - both are clickable.

## Read a task

The line is the task. For context, read the section it sits in:

```bash
rg -n -B5 -A5 'water filter' "wiki/personal/Home Tasks.md"
```

## Add a task

**Always check for duplicates first.** Grep for distinctive words from
the proposed title across the whole vault, including ticked lines:

```bash
rg -n -i '^\s*- \[[ x]\] .*water filter' wiki/ shared/
```

If anything plausible comes back, **stop and show it to the user**
("`Home Tasks.md:24` already has 'Decide between reverse osmosis and a
new replacement filter' - update that instead?"). A ticked line also
warrants a mention - the user may want to un-tick rather than re-add.

Once clear, pick the destination by the rules above and append the line
with `Edit`. Two judgement calls to get right:

- **Which note?** If the task names a thing that has a note, it goes
  there. Search by name before deciding there is no note:
  `fd -t f 'Yaris' wiki/`. Only fall back to `Home Tasks` / `Work Tasks`
  when nothing fits.
- **Which heading?** On `Home Tasks`, match the section. On a topic note,
  use its existing `## Tasks` heading, or add one before `## Log` /
  `## Related` if it has none.

## Close a task

Tick the box in place - `- [ ]` becomes `- [x]`. Leave it where it is,
or move it to a `## Done` section on the same page when the active list
gets noisy. Never move it to another page: a task in two places is a
task you tick in one of them.

## When to use this vs `/workbench:task-jira`

- **Personal life, hobbies, errands, household, family** → here.
- **DriveNets / AIE / DRV tickets, sprints, status transitions** →
  `/workbench:task-jira`.
- A vault task on a work page is still a personal note about work, not a
  JIRA ticket - use this skill. Reach for `/workbench:task-jira` only
  when the user mentions a real KEY or asks about JIRA explicitly.

If a request is ambiguous ("what should I work on today?"), check both:
grep the vault AND list the user's open JIRA issues, then let the user
pick.

## Pitfalls

- **Don't grep `data/`.** `data/tasks/data/` is the frozen archive of the
  old system and `data/` generally holds ledger rows, not tasks. Always
  scope to `wiki/` and `shared/`, and exclude `_attachments/`.
- **Checklists are not tasks.** A packing list, a game guide, or a recipe
  uses the same `- [ ]` syntax. Judge by the page, not the line - if the
  page is a checklist, its items are steps, not to-dos.
- **The line has no tags.** The page it sits on carries the tags. Filter
  by path, not by a tag on the line.
- **No created/modified date per line.** File mtime is the only age
  signal and it is weak - the file changes for unrelated reasons.
- For a live view inside Obsidian, the vault has `hubs/Tasks.md`, a
  Dataview query over every open line. It stores nothing.
