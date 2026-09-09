# Final-script style guide

Goal: a script that succeeds reliably AND fails informatively, so an agent (or a tired human) can fix it months later from the captured log.

Start from the template that matches the driver - `templates/harness-fetch-skeleton.py` (operator's Chrome) or `templates/playwright-fetch-skeleton.mjs` (own profile). Both encode the principles below.

## Principles

### 1. Follow-along logging

The log alone must answer: which step, what URL/state, what matched, why it stopped.

- `step: <label>` entering every step; the resulting URL and title after it.
- The actual selector/text/id that matched, not "clicked button".
- Long waits log around themselves - a silent 60s `waitFor` that times out tells you nothing.
- Playwright path: a screenshot + JSON snapshot of visible controls per step to `debug/<source>/<iso>-<n>-<label>.{png,snap.json}`, paths in the log. The template's `captureState()` does this.
- browser-harness path: log the tab id, the expression you evaluated (or a short label for it), and the status string it returned.

Prefix `[<script> <iso>]`, stderr only. No colours, no emojis - it's read by `tail -f` and by agents grepping.

### 2. Redaction

Never log cookie, authorization, or token values - not in the command you echo, not in the response you dump. When echoing headers, print an allowlist of names in clear (`content-type`, `accept`) and `name=<len N>` for the rest: a denylist of names (`/auth|token|key/i`) silently misses a header called `session`. Screenshots and DOM snapshots of a logged-in session are credentials by another name: `debug/` is gitignored, and if a log is handed to an agent it goes through a redactor first (blank the value after `cookie:`/`authorization:` up to end of line, not up to the next quote - cookie values contain quoted JSON).

### 3. Verify the output, not the exit

"File exists" is not success. Define success as records in the requested scope:

- Assert the scope (org, account, workspace, date window) in the page *before* exporting; fail loudly when it can't be confirmed. The wrong scope yields a valid, empty file - the one failure every naive check passes.
- Zero rows is a failure unless this source declares that empty is legitimate (a no-spend month). Say which in the docstring.
- If the endpoint ignores your date params, filter client-side and state the reachable window.

**Reconcile against a second number the provider publishes** - a total beside the rows, a running balance, a per-row identity (`quantity * rate == value`) - as a hard check. The row count survives a wrong field, a dropped row and a scaling mistake; a reconciliation does not.

**Prove the check bites once:** drop a row or multiply a number by ten, and confirm the message names the row.

**Iterating over ids doubles data when two ids name the same thing.** Per-unit identities all pass on a doubled result, because each copy is internally consistent. Assert the units you loop over are distinct - dedupe on the key the server itself keys on - and read a total that is an exact multiple of the UI's as this bug.

**Diff a few rows, every field, against the rendered UI before shipping.** The API's total and the page's table are independent witnesses; one field can be right on most rows and wrong on one.

**Units:** numeric APIs scale their numbers (minor units, quote units) and the scale can differ per row in one response. Prefer a field the provider already multiplied out over multiplying it yourself, derive a missing one from fields that reconcile, and check the identity on one row per class of thing, not on the first row.

### 4. Two failure classes, distinguishable to the caller

- **Needs a human**: signed out, 401/403, a missing role. Prefix the message `LOGIN:` (or use a dedicated exit code). Name the URL and what the operator must do.
- **Code is wrong**: endpoint changed, selector gone, timeout. Plain error.

A timeout is *not* evidence the session is bad - don't report it as a login problem. And never edit the script to route around missing auth.

### 5. Docstring for the next agent

Top of file, two kinds of facts:

- *Site quirks*: WAF, cross-origin login iframe, OTP on new device, class hashes that rotate, a deep link that 404s cold.
- *Data semantics*: rolling 30-day window, reporting lag behind the calendar, month-to-date only, params the endpoint ignores, columns absent upstream. These change what the script *requests*, so they belong next to the code that requests it.

Add a dated line for anything verified empirically ("verified 2026-08-30: 403 without header X").

Record the *negative* findings too: the field you deliberately did not emit and why, the total you chose not to reconcile against, the parameter the server ignores.

### 6. Secrets

- Operator's-Chrome path: the script holds **no** credentials. That's the point of it.
- Own-profile path: read from the project's convention (varlock + 1Password `op://` refs in personal repos, `.env`/env vars elsewhere); never on the command line, never hardcoded. Fail fast with a clear message when they're missing.

### 7. Contract with the caller

- One JSON line on stdout: `{"source": ..., "file": ..., "rows": N, ...}`. Nothing else on stdout.
- Honour the project's download-dir override (`<PROJECT>_DOWNLOAD_DIR` or an `OUT` path); default under the script's own dir.
- Move downloads out of `~/Downloads` and delete the original.
- Stamp rows with the provider's as-of date, not the run clock: "current" figures often settle a day or two behind, and a provider-dated row id makes a re-run idempotent.

### 8. Timeouts under the transport

No single driver call may outlive the driver's own timeout. Kick off the slow thing, poll a `window` global, read the result in a separate call. See `gotchas.md`.

### 9. Shared-browser hygiene (browser-harness)

Pin every call to your tab id. Close only tabs you opened; borrow an existing tab on the host when only the origin matters. One harness process at a time - two make each other's targets disappear.

### 10. Cleanup in `finally`

`try { ... } catch { exitCode = 1 } finally { await context.close() }` - or the Python equivalent. A leaked Chrome is cheap to prevent and expensive to notice.

### 11. Run it cold

After writing, run once from a clean state (not the explore session). Verify the success signal. On a detection-gated site a fresh profile can be blocked while the warmed one passes - re-run unchanged code on the known-good profile before assuming the script broke.

## Anti-patterns

- **Silent steps** - a bare `waitForSelector` with nothing logged around it.
- **One-shot selectors** - no fallback, no diagnostic of what *was* visible.
- **Try-and-fall-back against a live session** - each rejected request scores against the operator's reputation. Decide the path once, per source.
- **Hidden state** - "worked interactively, shipping it". Persistent state from exploration is invisible at runtime.
- **Over-cleaning** - don't `rm -rf debug/` in the script; that's the caller's job.
- **Untested dimensions reported as tested** - a loop over accounts, cards or currencies is untested when the operator's data holds exactly one. Name the branches that never ran.
