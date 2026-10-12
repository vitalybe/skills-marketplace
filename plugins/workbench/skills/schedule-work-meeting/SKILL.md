---
name: schedule-work-meeting
description: >-
  Schedules a work meeting end-to-end: resolves attendee names to emails,
  finds a mutually-free timeslot honoring working-hours and clustering
  preferences, and opens a prefilled Outlook invite ready to send. Use
  whenever the user wants to "schedule/set up/book a meeting", "find a
  time with <person>", "invite <person> to a meeting", "put something on
  my and X's calendar", or gives a subject + people + rough time. Handles
  optional people, date, time, and duration (default 30 min). Resolves
  names via the Outlook people API and disambiguates using the vault people
  registry. Distinct from /workbench:task-obsidian (personal to-dos) and
  /workbench:task-jira (work tickets).
---

# Schedule a work meeting

Turn a loose request ("meeting with Yinon, Sunday, 1hr, subject X") into a
prefilled, ready-to-send Outlook invite.

All calendar work goes through one CLI, which talks to Microsoft Graph
directly:

```bash
OC="node $HOME/hq/scripts/outlook-calendar/index.ts"
```

`$OC --help` and `$OC <command> --help` are the reference. Times are local
(`Asia/Jerusalem`), and the script handles timezone and DST itself.

## Inputs (all optional except at least one attendee)

- **Attendees** - names or emails.
- **Subject** - if it's missing, infer a short one or ask.
- **Date / day** - "Sunday", "tomorrow", "July 8". Default: today onward.
- **Time** - a specific start, or leave it open and pick from free slots.
- **Duration** - default **30 minutes**.
- **Window** - default **09:00-19:00 local**. This is a hard bound: the user
  set it deliberately, so never suggest slots outside it.

## Steps

### 1. Resolve attendees

```bash
$OC resolve "<name>"
```

The command prints matches best-first, ranked by how much the user interacts
with each person, as `Name <email> - title, department`.

- **One line** - use that email.
- **Several lines** - read `/Users/vbelman/obsidian/meta/people.md` for role
  and alias context, then ask the user to confirm. Show the top candidates,
  with your best guess first.
- **No match** - ask the user for the email.

Pass emails, not names, to the later commands. Those commands can resolve
names too, but they exit on any ambiguity.

### 2. Find slots

```bash
$OC free-slots --attendees a@x.com,b@x.com --duration 60 [--from 2026-10-18] [--days 5] [--window 09:00-19:00]
```

This command scans the next N workdays (Sun-Thu, starting from today and
skipping the past part of today). The organizer is always included. It
prints three sections:

- `TOP PICKS` - already ranked: fully free first, then slots between two of
  the user's meetings, then slots next to one, then the earliest. Each pick
  comes with a one-line reason.
- `EVERYONE FREE` - the merged free windows for each day.
- `ONE OR MORE TENTATIVE` - windows where someone is tentative or unknown,
  with the people holding them named.

If the result is empty, widen the scan with `--from` (the next week) or a
larger `--days`. Don't declare that no slot exists until you've done that.
Even then, say which days you covered and offer the tentative options.

If the user gave an exact time, run `free-slots` for that day only
(`--from <day> --days 1`) and check that the time shows up as free.

### 3. Propose and confirm

Show the top 2-3 picks with their reasons, recommend one, and get the user's
choice. Skip this step if the user gave an exact time and it's free.

### 4. Open the invite

```bash
$OC compose --title "<subject>" --start-time "2026-10-13 11:00" --duration 60 --attendees a@x.com,b@x.com
```

This opens an Outlook Web compose window in the default browser. Subject,
time and attendees are prefilled, and the window has a live **Send** button.
Nothing is sent until the user clicks it. Use `--no-open` to print the link
without opening the browser, and `--location` / `--body` for optional
fields.

Tell the user the invite is ready to send, and summarize the subject, local
time and attendees.

`$OC schedule` creates the event through Graph and **sends invitations
immediately**. Use it only when the user explicitly asks you to send the
invite yourself.

## Notes & gotchas

- **An attendee's own word beats their free/busy.** When the user relays "X
  said 16:30 works", book it even if the calendar disagrees. Flag the overlap
  in one line and move on.
- **"Unavailable" on an attendee chip** in OWA compose usually means free/busy
  hasn't loaded yet. Trust `free-slots`.
- **Auth:** the first run, or a run after the token expires, prints a
  device-code prompt to stderr. Relay the URL and code to the user, then wait
  for the user to sign in. The token cache is in `~/.cache/outlook-calendar/`.
- **Optional attendees:** the deeplink has no reliable parameter for them, so
  everyone is added as required. Mention this if it matters to the user.
- **Don't** create events with AppleScript against New Outlook: it doesn't set
  an organizer, so the invite can't be sent. Don't use `.ics` files either:
  they often open read-only.
