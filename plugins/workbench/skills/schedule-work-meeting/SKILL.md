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
  names via Slack/Outlook and disambiguates using the vault people
  registry. Distinct from /workbench:task-obsidian (personal to-dos) and
  /workbench:task-jira (work tickets).
---

# Schedule a work meeting

Turn a loose request ("meeting with Yinon, Sunday, 1hr, subject X") into a
prefilled, ready-to-send Outlook invite.

## Inputs (all optional except at least one attendee)

- **Attendee name(s)** - one or more people to invite.
- **Subject** - meeting title. If missing, ask or infer a short one.
- **Date / day** - e.g. "Sunday", "tomorrow", "July 8". Default: soonest sensible workday.
- **Time** - specific start, or leave open to pick from free slots.
- **Duration** - default **30 minutes** if unspecified.
- **Window** - default working hours **09:00-19:00 local** unless the user says otherwise.

## Tools used

- `mcp__claude_ai_Microsoft_365__get_me` - your identity / primary email.
- `mcp__claude_ai_Slack__slack_search_users` - resolve a name to a person + email.
- `mcp__claude_ai_Microsoft_365__find_meeting_availability` - mutual free/busy.
- `mcp__claude_ai_Microsoft_365__outlook_calendar_search` - your existing events (for clustering).
- `/Users/vbelman/obsidian/meta/people.md` - disambiguation registry (roles/aliases).
- The system default browser (`open <url>`) - to launch the prefilled invite.

There is **no MCP/connector that creates Outlook events**. Creation is done by
opening an **Outlook Web compose deeplink** (see step 6).

## Steps

### 1. Parse the request
Extract attendee name(s), subject, date, time, duration. Apply defaults
(duration 30 min; window 09:00-19:00 local). Note today's date and day-of-week
so relative days ("Sunday", "tomorrow") resolve correctly - and trust the
`nowDateTime` returned by the availability API over the system prompt if they
disagree.

### 2. Resolve each attendee to an email
For every name:
1. `slack_search_users` with the name.
2. **Exactly one hit** → use its email. No need to bother the user.
3. **Multiple hits** → read `people.md` to find the most likely candidate by
   role/context, then **ask the user to confirm**, presenting the top
   candidates (name, title, email) with your best guess first.
4. **Zero hits** → try `outlook_email_search` by name (matches senders/recipients
   across mail), or ask the user for the email.

Also call `get_me` to get your own primary email (you are the organizer).

### 3. Probe availability at 30-minute granularity

`find_meeting_availability` returns **one verdict per block of the `duration`
you ask for**. Ask for 90 minutes and a single busy half-hour anywhere inside
the block stamps the whole 90 minutes `busy` or `oof`. Coarse probes therefore
manufacture false negatives that read like hard facts: a real session reported
"he's out of office every afternoon" and "no window exists in the next month"
off 90-minute probes, and a 30-minute rescan of the same days found several
fully-free windows.

So **always probe with `duration: 30`**, whatever the meeting length, and do the
block-fitting yourself.

- One call **per candidate day**, with `afterDateTime`/`beforeDateTime` bounding
  that day's working window **in UTC** (Israel 09:00-19:00 local = 06:00-16:00Z
  in summer, 07:00-17:00Z in winter), `duration: 30`, `maxCandidates: 50`. Fire
  the days off in parallel. The current user is auto-included.
- Per-day matters because the API knows nothing about working hours and will
  happily offer 03:00. Hand it a multi-day range and day one's night hours eat
  all 50 candidates before it ever reaches day two.
- **A slot missing from the response means someone is busy then.** Read the
  gaps, not just the rows you got back.
- Each row carries an `availability` per attendee (`free` / `tentative` /
  `busy` / `oof`) plus `organizerAvailability` for the user. A slot is clean
  only when every one of those says `free`.
- Stitch consecutive clean slots into runs, then keep the runs at least as long
  as the meeting.

For clustering, also call `outlook_calendar_search` (query `*`) for **your own**
events across the candidate days - free/busy tells you a slot is open, not what
it sits next to. That works on the user's own calendar only; passing
`calendarOwnerEmail` for a colleague 404s (`ErrorItemNotFound`) without delegate
access, so don't spend a call on it - free/busy is all you get for other people.

**The working window is a hard bound, not a hint.** Don't drift below the floor
because a slot down there looks convenient; the user set 09:00 deliberately and
will correct you.

**Timezone care:** the availability API returns each slot's `dateTime` with a
`timeZone` field, and often falls back to **UTC** when the mailbox zone is
unavailable. Always convert to the user's **local** zone (Israel: UTC+3 in
summer / +2 in winter) before reasoning or presenting. Never show raw UTC to the
user.

### 4. Rank slots by preference
Among slots where **all attendees are free** and inside the working window:
1. Prefer slots **adjacent to an existing meeting** (back-to-back, before or
   after) - keeps the day clustered.
2. Prefer slots that **fill a gap between two existing meetings**.
3. Avoid fragmenting large free blocks and avoid `tentative` conflicts when a
   fully-free option exists.
4. Break ties by earliest in the day.

### 5. Propose and confirm
Show the top 2-3 ranked slots in **local time** with a one-line reason each,
recommend one, and get the user's pick. Skip if the user already gave an exact
time and it's free.

### 6. Create the invite via Outlook Web deeplink
Build this URL (this is the proven mechanism - no AppleScript, no ICS, works
regardless of New/Legacy Outlook):

```
https://outlook.office.com/calendar/deeplink/compose?subject=<SUBJECT>&startdt=<START>&enddt=<END>&to=<EMAILS>
```

- `<SUBJECT>` - URL-encoded subject.
- `<START>` / `<END>` - **naive local wall-clock** ISO, no timezone suffix,
  e.g. `2026-07-05T11:00:00` (OWA interprets these in the mailbox zone; do NOT
  append `Z`).
- `<EMAILS>` - comma-separated attendee emails for the `to=` param. This
  resolves each into a proper required-attendee chip.
- Optional: `&location=<enc>`, `&body=<enc>`.

Open it in the user's default browser (already logged into OWA):

```bash
open "https://outlook.office.com/calendar/deeplink/compose?subject=...&startdt=...&enddt=...&to=..."
```

The compose window opens with subject, time, and attendees prefilled and a live
**Send** button.

### 7. Hand off for send
Tell the user the invite is prefilled and they just need to click **Send**
(sending an invite is outward-facing - let the user do the final click unless
they explicitly ask you to auto-send). Summarize what was created: subject,
local date/time, attendees.

## Notes & gotchas

- **Never announce "no slot exists"** off a coarse or single query - that claim
  needs the 30-minute scan of step 3 across every candidate day behind it. If
  the scan genuinely finds nothing clean, say which days you covered and offer
  the best `tentative`-overlap options instead of declaring a dead end.
- **An attendee's own word beats their free/busy.** When the user relays "X said
  16:30 works", book it even if the calendar disagrees - people block time they
  are willing to give up. Flag the overlap in one line and move on; don't
  re-derive or argue the point.
- **"Unavailable" on an attendee chip** in the OWA compose often just means
  free/busy hasn't loaded yet, not a real conflict. Trust
  `find_meeting_availability` - if it says free, the slot is fine.
- **Do not** try to create the event with AppleScript against **New Outlook** -
  it won't attach an organizer/From, so the invite can't be sent. The deeplink
  avoids this entirely.
- **Do not** rely on `.ics` files or Apple Calendar AppleScript - the former
  often opens read-only, the latter silently drops attendees.
- If the user isn't logged into OWA in their default browser, they'll hit a
  sign-in once; after that the deeplink lands on the compose form.
- Multiple attendees: put them all in `to=` (comma-separated). There is no
  reliable deeplink param for optional attendees - keep everyone required, or
  mention the distinction to the user.
