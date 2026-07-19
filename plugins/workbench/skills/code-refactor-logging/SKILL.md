---
name: code-refactor-logging
description: Refactor logging and console output to follow structured logging standards — color scheme, log levels, prefix pattern, and output flow. Use when the user asks to clean up logging, standardize output, add structured logging, fix console messages, or when reviewing code that has inconsistent print/log/echo statements. Also applies when creating new CLI scripts or commands that produce user-facing output.
---

# Refactor: Structured Logging

Refactor logging and user-facing output to follow a consistent structured pattern. This pattern applies across languages (bash, JS/TS, Python, Go, etc.) — adapt the implementation to the language, but keep the principles and color scheme identical.

## The Pattern

Every log line follows this structure:

```
[prefix] message
```

Where `prefix` identifies the command (e.g., `worktree:add`, `tasks:find`) and is colored according to the log level.

### Example flow

```
[worktree:add] Task ID: DRV-37              ← value (white light on "DRV-37")
[worktree:add] Generating branch name...    ← debug (all dark gray, prefix included)
[worktree:add] Branch name: add-logo-DRV-37 ← value (white light on value part)
[worktree:add] Worktree path: /.worktrees/… ← value
[worktree:add] Creating worktree...         ← debug
[worktree:add] Running integration init...  ← debug
[worktree:add] Waiting for Claude init...   ← debug
[worktree:add] ✔ Claude is ready!           ← success (green prefix + ✔, plain message)
```

### Flow structure

Organize output in this order within a command:

1. **Input values** — show what was received/resolved (log_value)
2. **Operational steps** — what's happening now (log_debug)
3. **Result** — final outcome (log_success or log_error)

Don't repeat information. If you showed the branch name as a value, don't mention it again in the success line.

## Color Scheme

Six levels, each with a distinct color and purpose:

| Level   | Color      | ANSI         | Purpose                        | Prefix colored?   | Message colored?                           |
| ------- | ---------- | ------------ | ------------------------------ | ----------------- | ------------------------------------------ |
| error   | Red        | `\033[0;31m` | Errors, failures               | Yes (red)         | No (plain)                                 |
| warning | Yellow     | `\033[0;33m` | Warnings, non-fatal issues     | Yes (yellow)      | No (plain)                                 |
| success | Green bold | `\033[1;32m` | Final "done" lines             | Yes (green + ✔)   | No (plain)                                 |
| value   | —          | —            | Key values (IDs, paths, names) | No (plain)        | Value part only (white light `\033[0;97m`) |
| hint    | Cyan       | `\033[0;36m` | Suggestions, tips              | Context-dependent | Context-dependent                          |
| debug   | Dark gray  | `\033[0;90m` | Operational steps              | Yes (dark gray)   | Yes (dark gray)                            |

The core principle: **the prefix carries the level color, the message stays plain** (except debug where everything fades, and value where the value part is highlighted).

### Why this color mapping works

- **Debug is dark gray** — operational noise fades into the background. If everything went well, the user's eye skips right over it.
- **Values are white light** — bright but neutral. They stand out without implying status.
- **Success is green bold on the prefix only** — the ✔ draws the eye, but the message stays readable.
- **Errors/warnings color only the prefix** — the message itself is plain so it's easy to read and copy.

## Log Helpers

Each language should implement these helpers:

| Helper                    | Behavior                                                     |
| ------------------------- | ------------------------------------------------------------ |
| `set_log_prefix(prefix)`  | Sets the prefix for subsequent log calls                     |
| `log_msg(message)`        | `[prefix] message` — plain, no color                         |
| `log_debug(message)`      | `[prefix] message` — prefix + message both dark gray         |
| `log_value(label, value)` | `[prefix] label: value` — plain prefix, value in white light |
| `log_success(message)`    | `[prefix] ✔ message` — green prefix + ✔, plain message       |
| `log_warn(message)`       | `[prefix] message` — yellow prefix, plain message            |
| `log_error(message)`      | `[prefix] message` — red prefix, plain message               |

All log helpers write to **stderr**. Stdout is reserved for data output (return values, piped content, machine-readable output).

## Applying the Pattern

### Step 1: Set the prefix

Each entry-point function (subcommand, route handler, CLI action) sets its own prefix at the top:

```
set_log_prefix("<tool>:<action>")
```

Use the format `tool:action` — short, no spaces. Examples: `worktree:add`, `tasks:find`, `deploy:preview`.

### Step 2: Classify each log statement

Go through every `echo`, `console.log`, `print`, `log.info`, etc. and classify it:

- **Showing a resolved/computed value?** → `log_value`
- **Describing what's about to happen?** → `log_debug`
- **Final success of the command?** → `log_success`
- **Something went wrong?** → `log_error`
- **Non-fatal concern?** → `log_warn`
- **Data output for piping/consumption?** → Leave as stdout (don't use log helpers)

### Step 3: Remove noise

- Don't log what's obvious from context
- Don't repeat values that were already shown
- Don't narrate every micro-step — one debug line per meaningful phase is enough
- Remove redundant "Done:" lines if a success line already covers it

### Step 4: Verify the flow

Read the output top to bottom. It should tell a story:

1. Here's what I'm working with (values)
2. Here's what I'm doing (debug)
3. Here's the result (success/error)

## Reference Implementation (Bash)

This project's implementation lives in `src/_shared/script-utils.sh`. The color helpers (`color_error`, `color_success`, etc.) are internal — only `log_*` functions should be called directly from scripts.

## What NOT to Do

- Don't color entire messages — color only the prefix (or the value part in log_value)
- Don't use colors for decoration or emphasis within messages
- Don't mix raw `echo_stderr`/`console.error` with `log_*` calls in the same command
- Don't add logging to pure data-returning helper functions that output to stdout
- Don't log inside tight loops — log before and after
