---
name: herdr-watch-pane
description: "Event-driven monitoring of another herdr pane from an agent: run the bundled debounced watcher as a BACKGROUND task so the harness re-invokes you only when the watched pane's content settles after a real change (resize/scroll-immune, no wasted turns). Use when running inside herdr (HERDR_ENV=1) and you need to watch a sibling pane's output and react step-by-step - guiding a user through a setup wizard or installer they're driving, waiting on a long build or streaming logs, or following an interactive CLI - especially when you want to comment ONLY when something actually changes. Triggers: 'watch this pane', 'tell me when the pane changes / is done', 'monitor the wizard/installer/logs in the other pane', 'ping me only if it changes', 'guide me through X in a pane and react as it advances', 'loop every N seconds but only speak on change'. Optionally tracks progress and action items in a user-provided markdown file (e.g. a project wiki page) and updates it as steps complete."
---

# herdr-watch-pane — react when a herdr pane changes

Watch a *sibling* herdr pane and get woken up only when its content meaningfully changes, so you can guide or react to whatever is happening there (an interactive wizard the user drives, an installer, a build, a live log stream) without polling and without dumping the whole pane into your own context every few seconds.

## Prerequisites

- You are running inside herdr: `HERDR_ENV=1`. If not, stop - this skill controls herdr panes via its CLI. (See the `herdr` skill for pane/tab/workspace basics.)
- Know the target pane id. List panes and pick the non-focused one you want to watch:
  ```bash
  herdr pane list        # your pane is "focused": true; the target is a sibling
  ```

## The core idea

A background shell command that **blocks until the pane settles after a change, then exits**. The harness automatically re-invokes you when a background task exits, so the watcher's exit *is* your trigger. You react, then **re-arm** it for the next change. This beats a fixed-interval self-loop: no wasted wake-ups on "nothing changed", and it fires the instant the screen settles.

Do NOT use `ScheduleWakeup`/timers to poll a background task you started - when harness-tracked work finishes you are re-invoked automatically, so polling is pure waste.

## Quick start

The watcher script ships with this skill: `${CLAUDE_PLUGIN_ROOT}/skills/herdr-watch-pane/watch-pane.sh`.

1. Launch it as a **background** Bash task against the target pane:
   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/skills/herdr-watch-pane/watch-pane.sh <PANE_ID>
   ```
   Run it with `run_in_background: true`. It returns a task id and keeps running.
2. When the pane changes and settles, the task exits and you are re-invoked with a notification pointing at its output file. Read that file (or delegate the read - see below), interpret the new screen, and respond to the user.
3. **Re-arm**: launch the same command again as a background task to catch the next change. Repeat until the flow is done or the user says to stop.

Stop the chain any time with `TaskStop <task_id>`, or simply stop re-arming.

## Why the script is built the way it is (don't regress these)

- **Resize / scroll immune.** It reads `herdr pane read <PANE> --source recent-unwrapped`, i.e. scrollback with soft-wraps joined - independent of pane width and scroll position. Reading `--source visible` instead makes every resize or scroll fire a false change. (This is also the transcript `herdr wait output` matches against.)
- **Debounced.** On the first detected change it switches to 1s re-checks and only reports once the content is identical across a full interval - so you never wake on a half-drawn frame or a line the user is still typing. Reported output is tagged `CHANGED (settled)`.
- **Empty-read guarded.** Transient/failed reads (empty output) are skipped so a momentary hiccup doesn't false-trigger.
- **Bounded.** After `MAX_POLLS` idle polls it exits with a `no change after timeout` notice; just re-arm.

Tunable via args: `watch-pane.sh <PANE_ID> [MAX_POLLS] [POLL_SECS] [DEBOUNCE_SECS]`.

## Keeping YOUR context lean (recommended for long flows)

Each time you `Read` the watcher's output, the full pane dump lands in your context and stays. Over a long install that is the main source of bloat. To avoid it:

- Keep the **watcher in your (main) loop** - that re-trigger mechanism is reliable.
- When it fires, hand the **output file path** to a subagent and have it read + interpret and return a short summary (screen / state / suggested next step, < ~120 words). Only that summary enters your context. A *resumable* subagent (continue it via `SendMessage`) keeps its briefing, so you don't re-explain the flow each cycle.

Pitfall to avoid: do **not** ask the subagent to run the blocking watcher itself - a subagent tends to launch it as its own background task and then return prematurely ("waiting…"), orphaning the watcher. The subagent should only *read and summarize* an already-produced output file; the blocking watch stays in the main loop.

## Track progress in a markdown file

For any multi-step flow, ask the user for (or offer to create) a **markdown file to track progress and action items** - a project wiki page, a plan doc, a checklist. Then:

- Capture the steps as a checklist and tick items off as the pane advances.
- Record decisions, credentials-to-rotate, follow-ups, and open questions so nothing is lost between wake-ups.
- Keep it written to reflect the current state (no "previously / now" narration).

Suggested skeleton:

```markdown
## Setup & implementation tasks

### Done
- [x] ...

### In progress / next
- [ ] ...

### Follow-ups / open questions
- [ ] ...
```

If the vault/wiki is involved, the `/workbench:wiki` skill covers where such pages live; `/workbench:task-obsidian` covers personal task files.

## One-shot waits

If you only need to block until a *specific* string appears (not any change), prefer herdr's built-in `herdr wait output <PANE> --match "..." [--regex] --timeout <ms>` instead of this watcher. Use this skill when you want to react to *arbitrary* changes, screen by screen.
