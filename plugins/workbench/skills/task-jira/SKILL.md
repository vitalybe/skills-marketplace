---
name: task-jira
description: >-
  Reads, creates, edits descriptions, comments on, transitions, and searches
  JIRA issues using the `tasks` CLI (a Python single-file script from the
  ai-enablement repo, callable from anywhere once installed). Use this whenever
  the user asks to do anything JIRA-related: look up a ticket ("what is
  AIE-282", "show me FOO-123"), create or update an issue, change/append to a
  description, post a comment, move a status, list issues under an epic, fetch
  custom fields, or run a raw Atlassian REST call. Auto-triggers on bare KEY mentions like AIE-NNN / DRV-NNN, and
  on words such as "JIRA", "Atlassian", "issue", "ticket", "epic", "sprint",
  "transition", "status". Works in any folder; does not require being
  inside the ai-enablement repo.
---

# JIRA via `tasks`

A single dispatcher wraps `jira-cli` + the Atlassian REST API with auth
resolved from the macOS keychain. Same script everywhere - inside the
ai-enablement repo or outside it.

## Locate the script

Run this once at the start of any JIRA-flavoured turn to know which path
to invoke; cache it for the rest of the turn:

```bash
TASKS=$(command -v tasks || ls "$HOME/git/ai-enablement/_team_bin/tasks" 2>/dev/null)
[ -n "$TASKS" ] || echo "tasks not installed - clone ai-enablement and follow _team_docs/computer-setup.md → 'Use tasks from anywhere'"
```

For the rest of this doc, just write `tasks` - substitute `$TASKS` if it
isn't on PATH.

## Sanity-check auth (optional, only if a later call errors)

```bash
tasks rest GET /rest/api/3/myself
```

Returns the developer's Atlassian profile when auth is good. If it dies
with `[[Error: JIRA_API_TOKEN not available...]]`, the user hasn't put
their token in the keychain - tell them to run:

```bash
security add-generic-password -s jira-api-token -a "$USER" -w '<TOKEN>' -U
```

(Token comes from https://id.atlassian.com/manage-profile/security/api-tokens.)

## Subcommand cheat sheet

```
tasks show KEY                                    # full issue + comments
tasks list --parent EPIC [--status S]... [--limit N]
                                                    # list under an epic (parent accepts fuzzy summary or KEY)
tasks get-description KEY                          # print current description as markdown (read before editing)
tasks set-description KEY --from-file PATH         # replace description (markdown; fetch + fold in current first)
tasks comment KEY "body"                          # add a comment (rarely needed - prefer editing the description)
tasks comment KEY --from-file PATH                # add a comment (long body)
tasks set-state KEY STATE                         # canonical: Todo, In Progress, In Review, Done, Cancelled
tasks create --type T --parent K [--from-file P] [--attach P]... "Title"
                                                    # T in: Task, Sub-task, Bug, Story, Epic
tasks epics [--refresh]                           # cached epic list (24h)
tasks rest METHOD PATH [--data JSON | --data-file PATH]
                                                    # raw authenticated REST
tasks field-id "Field Name"                       # custom-field id resolver (24h cache)
tasks branch-name KEY                             # echo `slug-KEY` for branch naming
tasks plan KEY [TITLE]                            # plan file path (repo-only)
tasks flow-progress-get [KEY]                     # current devflow flow phase
tasks flow-progress-set [KEY] PHASE               # set devflow flow phase
tasks phases                                      # list canonical phase names
tasks help
```

`KEY` is auto-derived from the current branch suffix (matches
`[A-Z]+-[0-9]+$`) when omitted - so inside a `…-AIE-282` branch, you can
just type `tasks show`. Outside a git repo, pass `KEY` explicitly.

## Worked examples

### Look up a ticket

```bash
tasks show AIE-282
```

### Find / list / search

```bash
# Under an epic (fuzzy summary match on --parent)
tasks list --parent "Common Infra" --status "In Progress" --limit 20

# By multiple statuses
tasks list --parent AIE-120 --status Todo --status "In Progress"

# Raw JQL via REST
tasks rest GET '/rest/api/3/search/jql?jql=project=AIE+AND+assignee=currentUser()&fields=summary&maxResults=20'
```

### Update the description (the default)

When you add or change information on an issue, **edit the description** - it is
the canonical, durable home for the issue's content. Comments are for genuine
running commentary (a one-off "verified locally - merging", an FYI to a watcher)
and are rarely the right target. **When in doubt, default to the description.**

**Always read before you write.** `set-description` *replaces* the whole
description, so fetch the current one, fold your change into it, and write the
complete result back - never blindly overwrite:

```bash
tasks get-description AIE-282 > /tmp/desc.md   # current description as markdown
# edit /tmp/desc.md: fold in the new content, keep what's already there
tasks set-description AIE-282 --from-file /tmp/desc.md
```

`set-description` feeds markdown through jira-cli's markdown → ADF conversion, so
headings, lists, **bold**/*italic*/`code`, and links round-trip. It refuses an
empty body, and leaves other fields (summary, status) untouched. For multiline
bodies always go through a `/tmp` file + `--from-file` (never heredocs/`echo`).

**If the request sounds like a comment, ask first.** Phrasings like "comment
that…", "post a note", "leave an FYI", or a status update aimed at watchers may
genuinely want a comment instead of a description edit. When the target is
ambiguous, ask the user **"description or comment?"** before writing - do not
silently pick.

### Comment (rarely)

```bash
# Short body - only for genuine running commentary, not issue content
tasks comment AIE-282 "Verified locally - merging."

# Long body: write to /tmp first, then pass --from-file
# (avoid heredocs / printf / shell-quoting headaches)
tasks comment AIE-282 --from-file /tmp/note.md
```

### Transition status

```bash
tasks set-state AIE-282 "In Review"
tasks set-state AIE-282 Done
```

If a target status isn't reachable in one hop, the dispatcher walks up
to one intermediate transition automatically.

### Create an issue

**Always check for duplicates first.** Before calling `tasks create`,
search the same project (and parent, if known) for an existing issue
with a similar summary. Re-using or commenting on an existing ticket is
almost always preferable to creating a near-duplicate.

```bash
# Pull 2-3 distinctive keywords from the proposed title, then search.
# Project comes from the parent KEY prefix (e.g. AIE-120 → project=AIE).
tasks rest GET '/rest/api/3/search/jql?jql=project=AIE+AND+statusCategory!=Done+AND+summary~%22cost+dashboard%22&fields=summary,status&maxResults=10'

# Or, if the parent is known, list open issues under it and eyeball:
tasks list --parent AIE-120 --status Todo --status "In Progress" --limit 50
```

If the search returns plausible matches, **stop and show them to the
user** ("AIE-281 looks like the same thing — comment there instead?").
Only proceed to `tasks create` when the user confirms it's new, or when
the search is empty. Done/Cancelled hits still warrant a heads-up - the
user may want to reopen rather than file fresh.

```bash
# Plain task under a known epic
tasks create --type Task --parent AIE-120 "Add foo to bar"

# Body + attachment
tasks create --type Bug --parent AIE-122 \
    --from-file /tmp/body.md --attach /tmp/screenshot.png \
    "Cost dashboard chart misaligned"

# Sub-task under a parent task
tasks create --type Sub-task --parent AIE-282 "Backfill tests"
```

`--parent` accepts a KEY or a fuzzy substring match on epic summaries.
The new KEY is printed on stdout (or the browse URL on a TTY).

### Custom fields and raw REST

```bash
tasks field-id "AI Workflow"                       # -> customfield_NNNNN
tasks rest GET /rest/api/3/issue/AIE-282/transitions
tasks rest PUT /rest/api/3/issue/AIE-282 \
    --data '{"fields":{"labels":["foo","bar"]}}'
```

`tasks rest` only speaks JSON. For multipart endpoints, use the
`--attach` flag on `tasks create`, or hit the endpoint with `requests`
in a Python one-liner (the auth path is the same: env, then keychain).

### Assign an issue / set priority

Resolve the person to an `accountId`, then PUT it:

```bash
tasks rest GET '/rest/api/3/user/search?query=nadav'   # -> accountId + displayName + email
tasks rest PUT /rest/api/3/issue/AIE-282 \
    --data '{"fields":{"assignee":{"accountId":"712020:92b8..."},"priority":{"name":"High"}}}'
```

**Name disambiguation:** when the user says just **"Nadav"**, they mean
**Nadav Cohen** (`nacohen@drivenets.com`) - assign him without asking.

## Output contract

- **stdout** = the result (KEY, JSON, formatted issue, etc.).
- **stderr** = progress chatter (`refreshing cache...`, `creating Task...`).
- **Errors land on stdout** in one of two forms:
  - TTY: `Error: <msg>` (colored).
  - Captured by `$()` / pipe: `[[Error: <msg>]]` (marker form).

When you capture output, always check for the `[[Error:` prefix before
treating it as a value:

```bash
out=$(tasks branch-name AIE-282)
case "$out" in
  '[[Error:'*) echo "tasks failed: $out" >&2; exit 1 ;;
esac
```

## Pitfalls

- Issue types are case-sensitive: `Task`, `Sub-task` (note the hyphen),
  `Bug`, `Story`, `Epic`.
- Multiline comment / description bodies → always write to
  `/tmp/<name>.md` and pass `--from-file`. Do not use heredocs, `printf`,
  or `echo` - shell-quoting bugs are silent and lose newlines.
- `plan` and KEY-from-branch only work inside a git repo. Pass `KEY`
  explicitly to use the other subcommands from anywhere.
- The first call after 24 h refreshes the field/epic cache - ~1-2 s
  of expected overhead, surfaced as `refreshing JIRA …` on stderr.
- Inside the ai-enablement repo with env loaded (varlock/direnv), the
  env `JIRA_API_TOKEN` wins over the keychain. That's intentional - it
  lets you swap tokens per-repo if you ever need to.

## When to drop down to raw `jira-cli`

Almost never. `tasks rest` plus the subcommands cover every Atlassian
REST endpoint and the common jira-cli flows. Reach for `jira` directly
only when the user explicitly asks for it.
