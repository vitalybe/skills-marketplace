# Final-script style guide

The goal: a script that succeeds reliably in production AND fails informatively, so that when an agent (or a tired human) has to debug it months later from just the captured log output, they can.

## Two production reference scripts

These exist in the user's repo and are the gold standard to match:

| Path | Approach | When to model after |
|------|----------|---------------------|
| `~/hq/finance-importer/finance-max-account.mjs` | agent-browser via `spawn("agent-browser", ...)` | When agent-browser handled the full flow during exploration |
| `~/hq/finance-importer/finance-cal-account.mjs` | Playwright `chromium.launchPersistentContext` | When the site has cross-origin iframes, OTP, or other agent-browser blockers - use puppeteer in the same shape |

Read whichever one matches the path you took during exploration before writing the new script. The `~/hq/finance-importer/README.md` documents the project conventions (varlock schema, `FINANCE_DOWNLOAD_DIR`, parser naming).

## The non-negotiable principles

### 1. Heavy progress logging — the agent must follow along from logs alone

The single most important principle. If something breaks at 3am and the only thing in the captured output is `FAIL: timeout`, the next agent has to re-run the whole flow to debug. That's wasted time and money. Instead, log enough that the captured output tells the full story:

- A `step: <label>` line entering every step.
- After every navigation or DOM transition: the new URL, page title, and a count of visible buttons / inputs / iframes.
- Every actual interaction: the selector or text that matched, not just "clicked button".
- On every step, a screenshot AND a JSON snapshot of visible elements to `./debug/<source>/<timestamp>-<step>.png` and `.snap.json`. Log the paths so the captured output references them.

Concretely, every step looks like this in the log:

```
[finance-cal-account 2026-05-16T13:36:00.123Z] step: switch-to-username-tab
[finance-cal-account 2026-05-16T13:36:00.480Z]   state[007]: after-switch-to-username-tab | url=https://digital-web.cal-online.co.il/calconnect/regular-login | title="CalConnect" | btns=6 iframes=0 | png=./debug/cal/2026-05-16T13-36-00-480Z-007-after-switch-to-username-tab.png snap=./debug/cal/2026-05-16T13-36-00-480Z-007-after-switch-to-username-tab.snap.json
```

The agent reading this knows: which step, which URL, page changed (or didn't), how many interactive things are visible, and where to look for the screenshot + structured DOM dump if it needs more. No re-running required.

The skeleton template (`templates/final-script-skeleton.mjs`) implements this in a `captureState(page, label)` helper invoked after every `step()`. Use it.

### 2. Secrets via varlock - never hardcoded, never on the command line

In the user's hq repo, every fetcher uses varlock to resolve secrets from 1Password:

```js
// Set cwd to the script's dir so varlock finds .env.schema, then restore.
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
{
  const originalCwd = process.cwd();
  process.chdir(SCRIPT_DIR);
  await import("varlock/auto-load");
  process.chdir(originalCwd);
}
const USER = process.env.ACCOUNT_<SOURCE>_USER;
const PASS = process.env.ACCOUNT_<SOURCE>_PASS;
if (!USER || !PASS) {
  console.error(`[finance-<source>-account] varlock did not populate creds - check .env.schema`);
  process.exit(1);
}
```

The `.env.schema` entry uses an `op(...)` reference:

```
ACCOUNT_<SOURCE>_USER=op("op://Private/<item-id>/username")
# @sensitive
ACCOUNT_<SOURCE>_PASS=op("op://Private/<item-id>/password")
```

If the user is on a project without varlock, ask before writing - sometimes the right answer is plain env vars or `.env` via dotenv. Match the project's existing convention.

### 3. Honor FINANCE_DOWNLOAD_DIR (or the project's equivalent override)

The orchestrator (`/p-wiki-finance-process`) sets `FINANCE_DOWNLOAD_DIR` to a fresh tmp dir per run. Manual runs without it should default to `./downloads/<source>/`:

```js
const DOWNLOAD_DIR = process.env.FINANCE_DOWNLOAD_DIR ?? join(SCRIPT_DIR, "downloads", "<source>");
mkdirSync(DOWNLOAD_DIR, { recursive: true });
```

### 4. Module docstring documenting why this site is unusual

Every fetcher has a top-of-file comment block explaining the quirks. Examples:

- "cal-online.co.il is fronted by a BIG-IP ASM WAF that rejects most headless UAs."
- "Login form lives inside a cross-origin same-site iframe (connect.cal-online.co.il)."
- "First login from a new device requires an SMS OTP."

These notes prevent the next agent from re-discovering the same gotchas. Add a line for everything tricky you found during exploration.

### 5. try/catch/finally with guaranteed browser cleanup

```js
let exitCode = 0;
try {
  await main();
} catch (err) {
  log(`FATAL: ${err.message}`);
  exitCode = 1;
} finally {
  await browser.close().catch(() => {});
}
process.exit(exitCode);
```

Skip `.close()` and you leak Chrome processes - cheap to do, easy to forget.

### 6. Logging conventions

- Prefix: `[<script-name> <iso-timestamp>] `. Always stderr (stdout is for data if any).
- A `step(label, fn)` wrapper logs entry, runs the work, captures debug state, and propagates errors with the label included.
- No emojis, no colors. Plain text - it's read by tail -f and by agents grepping log files.

### 7. Run the final script once before declaring done

After writing the production script, run it cold (not from the explore state). Verify the success signal (file on disk, expected size, etc.). Fix anything that breaks - exploration state can mask bugs that show up only on a clean run (e.g., login redirects, cookie-banner popups that don't appear when the profile already accepted them).

## Anti-patterns

- **Silent steps.** A 60-second `await page.waitForSelector(...)` with no log line in between. If it times out, you have no idea why - did the URL change? Was the selector wrong? Was the network slow? Log around long waits.
- **One-shot selectors.** `await page.click("button.primary")` with no fallback and no diagnostic. When that breaks (and it will), the script just fails with no clue. Wrap in `step()` and capture state.
- **Hidden state.** "It worked once interactively, so I'll just commit it." Persistent state from the explore session is invisible at production runtime. Test with a fresh profile dir at least once.
- **Cleaning up too aggressively.** Don't `rm -rf debug/` in the script. The debug artifacts are exactly what you need to debug the next failure. The orchestrator's job to garbage-collect, not the fetcher's.
