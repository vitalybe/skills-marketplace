---
name: browser-automation-explore-and-script
description: Build a reliable browser-automation script for a website by first recording the flow with Playwright codegen, then translating it into a replayable script using agent-browser (preferred) or falling back to puppeteer. Use whenever the user wants to "automate this site", "write a scraper for X", "build a fetcher / downloader for Y", "log in to Z and grab N", "turn this manual web flow into a script", or asks for a new finance fetcher / bank statement downloader / web scraper / form filler / login automation - even if they don't explicitly mention Playwright, puppeteer, or codegen. Especially relevant when the target site has logins, iframes, OTP, downloads, or anti-bot defenses that make naive automation flaky.
---

# Browser automation: explore-then-script

This skill helps the user produce a **reliable, runnable** automation script for a website they describe. The script needs to work on the user's machine, not just once in a sandbox - so the workflow is built around *exploration first*, *codification second*.

The core insight: writing browser automation against a site you've never poked at is a recipe for fragile selectors and missed edge cases. So we record the human flow once, replay it interactively to discover the gotchas, then commit a script that already accounts for them.

## When to use this

Trigger whenever the user wants to drive a website from a script - login, fill a form, click through, scrape data, download a file, etc. The user almost never says "use Playwright codegen" - they say "automate this", "build a fetcher", "scrape this", "log in and grab the bill". That's your cue.

If the user already has a working script and just needs a small tweak, skip this skill and edit the script directly. This skill is for **new** automation work or **major rewrites**.

## Why this workflow (read this before improvising)

Three tools, each good at one phase:

- **Playwright codegen** records a real human session into a `.spec.ts` file with the exact selectors Playwright's locator engine settles on. It's the cheapest, most accurate way to capture "what the user actually does". The output is rarely the final script, but it's a *truthful map* of the flow.
- **agent-browser** is the user's preferred CLI for re-running flows because it's batteries-included (auth vault, session persistence, downloads, snapshot/screenshot, simple ref system). When agent-browser works, scripts stay short and readable. Try it first.
- **Puppeteer** is the fallback because Node-level CDP control unlocks things agent-browser can't reach: cross-origin iframes, custom event chains (Angular Material!), download-progress wiring, session-id-in-URL SPAs that die on reload, and arbitrary `evaluate()` inside any frame.

The order matters: codegen tells the truth about the human flow, agent-browser produces the cleanest scripts when it can, and puppeteer is the escape hatch that always works.

## Workflow

Do this top to bottom. Each phase produces an artifact that feeds the next.

### Phase 0: Capture intent

Ask the user (one short message, two questions):

1. **Site + flow** - what URL, what does the script need to accomplish end-to-end. ("Log in to bank X, download last month's statement to ~/Downloads/")
2. **Where the final script lives** - absolute path. Suggest a sensible default based on context (e.g., for finance work, `~/hq/finance-importer/finance-<source>-account.mjs`). Don't bikeshed - if they're vague, propose a path and let them redirect.

If the target site needs credentials, also ask **how to read them**. For this user's repo the canonical answer is varlock + 1Password (`op://...` refs). For other repos it might be env vars or a `.env`. Don't guess - one question saves a rewrite later. See `references/final-script-style.md` for the varlock pattern.

### Phase 1: Record with Playwright codegen

Tell the user you're about to launch codegen and they should perform the entire flow once in the window that pops up - including any waits/clicks/text input. Codegen records continuously and writes to stdout.

```bash
# Use a tempfile so we capture the output even if the user closes the window
CODEGEN_OUT=$(mktemp -t codegen-XXXXXX.spec.ts)
npx playwright codegen --output "$CODEGEN_OUT" <URL>
# (control returns when the user closes the codegen window)
cat "$CODEGEN_OUT"
```

If `playwright` isn't installed, run `npx -y playwright@latest install --with-deps chromium` first, or `cd` into a directory that has playwright as a dep (e.g. `~/hq/finance-importer`).

Once codegen exits, read the file. Codegen output is verbose but high-signal - the `await page.getByRole(...)`, `await page.frameLocator(...)`, and URL patterns it captures are exactly the selectors that work on the real page. Note any iframes (`frameLocator`), file uploads/downloads, and waits.

### Phase 2: Replay with agent-browser (preferred path)

Translate each codegen step into agent-browser commands and run them interactively - one or a few at a time, snapshotting between. The agent-browser skill (already installed, see `~/.claude/skills/agent-browser/SKILL.md`) documents the CLI surface. Use a **named session** so concurrent agents don't fight, and a **persistent profile** if login should survive between runs:

```bash
SESSION=explore-<site>
agent-browser --session "$SESSION" --profile ~/.local/share/agent-browser-profiles/<site> open <url>
agent-browser --session "$SESSION" snapshot -i           # discover refs
agent-browser --session "$SESSION" find label "Email" fill "$USER"
agent-browser --session "$SESSION" find role button click --name "Sign in"
agent-browser --session "$SESSION" wait --url "**/dashboard"
agent-browser --session "$SESSION" snapshot -i           # confirm state changed
```

After each step that should change the page, take a fresh snapshot or `diff snapshot` to verify. When a click silently fails, **don't keep stacking actions on top** - stop, snapshot, screenshot, and figure out why before continuing. That's the explore loop.

If credentials are needed, do **not** type them on the command line - either:
- pipe via stdin (`echo "$PASS" | agent-browser auth save ...`), or
- have agent-browser read them from a saved auth profile (`agent-browser auth login <name>`), or
- in the interactive explore phase, ask the user to enter them in the browser window themselves (the persistent profile will remember the session for the script run).

#### When to declare agent-browser stuck

agent-browser cannot reach (or reliably drive) some surfaces. If you hit any of these and a workaround isn't obvious in a few minutes, **stop and move to Phase 3**:

- **Cross-origin iframes**. agent-browser's snapshot system inlines same-origin frames but cross-origin frames are opaque. (Some sites mount login forms on a `connect.<vendor>.com` or `auth.<vendor>.com` iframe - those will not be drivable.)
- **Custom Angular Material / Web Component clicks** that swallow the standard `click` event. Symptom: `agent-browser click @e1` returns success but the UI doesn't change. (Material's `mat-tab-link` is a classic case.)
- **Download flows that need a custom destination directory** or that race with the page navigation. agent-browser has `--download-path` and `wait --download`, but custom routing is fiddly.
- **SPAs that put a session id in the URL** (`?sid=...`) and 401 you on reload - hard to recover from inside agent-browser's stateless command model.
- **OTP / SMS / 2FA** where the operator must type a code - workable in agent-browser but the round-trip through the CLI is painful; puppeteer's headed-with-pause is usually nicer.

When you stop, tell the user *why* in one sentence ("agent-browser can't see inside the login iframe, switching to puppeteer") - they may know a shortcut you don't.

### Phase 3: Replay with puppeteer (fallback path)

The puppeteer fallback uses an **incremental WS-based pattern**: one long-running launcher process owns the headed browser, and short step-scripts connect to it over CDP to run individual actions. This is exactly the same explore-then-codify rhythm as Phase 2, just with more raw control.

#### One-time setup

```bash
cd <project-dir>
pnpm add -D puppeteer       # or npm/yarn
# If puppeteer's bundled Chrome download is corrupt or you want to use an existing one,
# the launcher template accepts an executablePath - point at an already-installed Chrome
# (agent-browser ships one at ~/.agent-browser/browsers/chrome-*/Google Chrome for Testing.app/...).
```

#### Start the launcher

Copy `templates/puppeteer-launcher.mjs` into the project (typically as `_explore-launcher.mjs` - the leading `_` marks it as exploration scrap, not a real fetcher), edit the URL / profile dir / Chrome path, and run it in the background:

```bash
node _explore-launcher.mjs &     # writes ws endpoint to /tmp/explore-puppeteer-ws
```

The launcher opens the site in a visible Chrome window, prints the CDP WS endpoint to `/tmp/explore-puppeteer-ws`, and stays alive until you close the window.

#### Drive it incrementally

Copy `templates/puppeteer-step.mjs` into the project as `_explore-step.mjs`. It's a one-shot CLI that connects via WS and runs a single op:

```bash
# Quick probes
node _explore-step.mjs '{"op":"url"}'
node _explore-step.mjs '{"op":"snapshot"}'
node _explore-step.mjs '{"op":"screenshot","path":"/tmp/state.png"}'
node _explore-step.mjs '{"op":"eval","fn":"() => ({ title: document.title, w: innerWidth })"}'

# Actions
node _explore-step.mjs '{"op":"click","selector":"#login-btn"}'
node _explore-step.mjs '{"op":"text","needle":"Sign in","tag":"button"}'
node _explore-step.mjs '{"op":"goto","url":"https://example.com/dashboard"}'
```

For anything more complex than the built-in ops, write a one-off `node -e '...'` that connects via `puppeteer.connect({ browserWSEndpoint: ... })` and does whatever you need - including walking iframes via `page.frames()`, dispatching pointer events, reading networks, etc. The step-runner is just a convenience for common ops.

When something works, **don't lose it** - paste the working snippet into a scratch file or into the eventual final script. Iteration moves fast; memory doesn't.

#### Patterns to know before you start fighting selectors

These are real gotchas that have cost hours in past sessions. Read `references/puppeteer-gotchas.md` before debugging anything mysterious - it's organized by symptom so you can grep.

### Phase 4: Write the final script

Once the flow works end-to-end in exploration, write the production script to the path the user named in Phase 0.

**The single most important property of the final script: it must log heavily enough that an agent reading the captured output later can tell exactly where it got to, what state the page was in, and (if it failed) why - without re-running the script.** That means after every meaningful step:

- The new URL and page title.
- A compact count + summary of visible buttons / inputs / iframes.
- A screenshot AND a JSON snapshot of visible elements written to `debug/<source>/<iso>-<step>.{png,snap.json}`, with both paths logged.

This is non-negotiable. A script that fails at 3am with just `FAIL: timeout` is a script that costs you another full debug session. A script that fails with the URL it was on, the buttons it could see, and a snapshot path it can grep, is one an agent can fix from logs alone. The skeleton template implements this in a `captureState(page, label)` helper called on every `step()` boundary - keep that pattern.

Modeling guidance:

- If you got there via **agent-browser**, model on `~/hq/finance-importer/finance-max-account.mjs`.
- If you got there via **puppeteer**, model on the skeleton (`templates/final-script-skeleton.mjs`) and look at `~/hq/finance-importer/finance-cal-account.mjs` for the persistent-profile + try/catch/finally shape.

Other essentials covered in `references/final-script-style.md`:
- Secrets via varlock (`await import("varlock/auto-load")` after `chdir(SCRIPT_DIR)`), never on the command line.
- Top-of-file module docstring listing *why this site is unusual* - the WAF, the iframe, the OTP, etc. Future-you will thank present-you.
- Honor `FINANCE_DOWNLOAD_DIR` (or the project's equivalent) so the orchestrator can route downloads.
- `try { ... } catch { exitCode = 1 } finally { await browser.close() }` so the browser never leaks.

Read `references/final-script-style.md` in full before writing - the principles there are what separates a script that survives the next site redesign from one that doesn't.

Then **run the final script end-to-end once on a clean invocation** (not from the explore loop's state). Fix anything that breaks - exploration state can mask bugs that only show up cold (cookie banners, login redirects, popups the persistent profile already dismissed). Report the result with the success signal (downloaded file path + size, scraped row count, etc.).

### Phase 5: Cleanup

- Delete the `_explore-*.mjs` scrap files unless the user wants them kept.
- Kill any background browser still running (`kill $(pgrep -f _explore-launcher)` or close the window).
- If you used a session-name with agent-browser, run `agent-browser --session <name> close`.

## What good final scripts look like

See `references/final-script-style.md` for the full pattern. The short version:

1. Top-of-file module docstring explaining *why this site is unusual* (WAF, iframe, OTP, etc.) - these notes are gold for the next agent who has to fix it after the site redesigns.
2. Env loading via varlock (`await import("varlock/auto-load")` after `chdir(SCRIPT_DIR)`).
3. Constants up top: `DOWNLOAD_DIR`, `PROFILE_DIR`, `HEADED`, etc., each with a one-line comment explaining the default.
4. Structured logging: `[<script-name> <iso>] <message>` to stderr; never to stdout (stdout is for data).
5. Steps wrapped in a `step(label, fn)` helper that captures URL + screenshot + a11y snapshot on failure to `debug/<source>/`.
6. `try { ... } catch { exitCode = 1 } finally { await browser.close() }` so the browser never leaks.

## Bundled resources

| File | Purpose |
|------|---------|
| `references/puppeteer-gotchas.md` | Symptom-indexed gotcha guide for the fallback path |
| `references/final-script-style.md` | Production-script conventions (varlock, logging, debug capture) |
| `templates/puppeteer-launcher.mjs` | Headed Chrome launcher that writes WS endpoint to a tmp file |
| `templates/puppeteer-step.mjs` | One-shot step runner over WS (ops: url, eval, click, text, goto, snapshot, screenshot) |
| `templates/final-script-skeleton.mjs` | Starting point for the production script with `captureState()` / `step()` logging baked in |

## Live examples in the user's repo

These are the actual scripts the workflow has produced, kept around as reference:

- `~/hq/finance-importer/_explore-cal-launcher.mjs` — real launcher used to drive cal-online interactively
- `~/hq/finance-importer/_explore-cal-step.mjs` — real step-runner used in the same session
- `~/hq/finance-importer/finance-max-account.mjs` — production agent-browser-style fetcher
- `~/hq/finance-importer/finance-cal-account.mjs` — production playwright-persistent-context fetcher

When the user is in this repo, read these alongside the bundled templates - the templates are starting points, but the in-repo examples show the conventions actually in use.
