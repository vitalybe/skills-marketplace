---
name: code-refactor-pretty-cli
description: Give a Node CLI script pretty terminal output with @clack/prompts (intro/outro, spinners per step, notes, confirm prompts) while keeping a plain-text run log that an agent can read later to debug a failed run. Use when the user asks to "make the output pretty", "add spinners", "use clack", "make this script nicer to watch", or when writing a new long-running Node script (fetchers, importers, migrations, deploy steps) that a human watches in a terminal AND an orchestrator or agent runs unattended. Distinct from /workbench:code-refactor-logging, which is the plain colored-prefix standard for short shell-style scripts with no spinners or prompts.
---

# Pretty CLI with an agent-readable log

Two audiences, two sinks. A human watching a terminal wants spinners and a short summary. An agent fixing the script tomorrow wants every step, URL, path, and error in one plain file it can grep. Serve both, never mix them.

## The rules

1. **The run log file is the source of truth.** Every step, value, warning, error, and artifact path goes to `<debug-dir>/<run-stamp>.log` as `[<name> <iso>] <message>`. No colors, no box characters, no emojis. Write it even when the terminal shows nothing.
2. **Clack only on a TTY.** Check `process.stderr.isTTY`. When false (orchestrator, CI, an agent's shell), print plain `[<name>] <message>` lines to stderr instead. Clack's borders and spinner frames are noise in a captured log.
3. **Stdout is for data.** All UI and logging goes to stderr. Piping the script's stdout must still work.
4. **One spinner per step.** `spinner().start(label)` before the work, `stop(label + result)` on success, `stop(message, 2)` on failure. Never nest spinners, never print inside a running spinner (use the log file).
5. **Prompts are TTY-only and cancellable.** Guard every `confirm` / `text` with the TTY check and handle `isCancel`. A non-TTY run that needs a prompt fails with a message saying to rerun in a terminal.
6. **On failure, print the recovery.** The final lines on a failed run are the error and a `note` containing what to run next, including the log path. That is what the human copies.

## The pattern

```js
import * as p from "@clack/prompts";
import { appendFileSync } from "node:fs";

const NAME = "<tool>:<action>";
const TTY = Boolean(process.stderr.isTTY);
const LOG_FILE = `<debug-dir>/${new Date().toISOString().replace(/[:.]/g, "-")}.log`;

const fileLog = (msg) => appendFileSync(LOG_FILE, `[${NAME} ${new Date().toISOString()}] ${msg}\n`);
const out = (kind, msg) => {                 // kind: info | success | warn | error | step
  fileLog(kind === "info" ? msg : `${kind}: ${msg}`);
  if (TTY) p.log[kind](msg);
  else process.stderr.write(`[${NAME}] ${msg}\n`);
};

async function step(label, fn) {
  const s = TTY ? p.spinner() : null;
  s?.start(label);
  fileLog(`step: ${label}`);
  try {
    const result = await fn();
    s?.stop(label);
    if (!TTY) process.stderr.write(`[${NAME}] ${label}\n`);
    return result;
  } catch (err) {
    s?.stop(`${label}: ${err.message}`, 2);
    throw new Error(`${label}: ${err.message}`, { cause: err });
  }
}

if (TTY) p.intro(NAME);
try {
  await step("fetch", () => doWork());
  if (TTY) p.outro("done");
} catch (err) {
  out("error", err.message);
  if (TTY) p.note(`see ${LOG_FILE}`, "to debug"); else process.stderr.write(`[${NAME}] see ${LOG_FILE}\n`);
  process.exitCode = 1;
}
```

Prompting the user mid-run:

```js
if (!TTY) throw new Error("needs a terminal - rerun interactively");
const ok = await p.confirm({ message: "Continue?" });
if (p.isCancel(ok) || !ok) throw new Error("aborted");
```

Install: `pnpm add @clack/prompts` (ESM, no other deps).

## Applying it to an existing script

1. Add the two sinks (`fileLog`, `out`) and the `step()` wrapper at the top.
2. Wrap each meaningful phase in `step()`. One phase per spinner, not one per line of work.
3. Route every `console.log` / `console.error` through `out()` or `fileLog()`. Verbose diagnostics (element dumps, byte counts, poll ticks) go to `fileLog` only.
4. Leave stdout data output untouched.
5. Run it once on a TTY and once piped (`node x.mjs 2>&1 | cat`). The piped output must be plain lines and the log file must tell the whole story on its own.

## What NOT to do

- Don't wrap every helper in a spinner - the terminal should show a handful of steps, not fifty.
- Don't put values only in the spinner text. Anything an agent may need goes to the log file too.
- Don't call `p.log.*` or `p.note` outside the TTY guard.
- Don't `rm` the log or debug directory from the script. Cleanup is the caller's job.
