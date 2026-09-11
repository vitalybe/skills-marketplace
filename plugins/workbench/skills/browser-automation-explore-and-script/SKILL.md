---
name: browser-automation-explore-and-script
description: Build a reliable browser-automation script for a website by recording the flow with Playwright codegen, exploring it interactively (browser-harness against the operator's own Chrome, or a Playwright persistent profile), then committing a replayable script that verifies its own output. Use whenever the user wants to "automate this site", "write a scraper for X", "build a fetcher / downloader for Y", "log in to Z and grab N", "turn this manual web flow into a script", or asks for a new finance fetcher / statement downloader / web scraper / form filler / login automation - even if they don't mention Playwright, codegen, or browser-harness. Especially relevant when the target site has SSO, 2FA, iframes, downloads, or anti-bot defenses that make naive automation flaky.
---

# Browser automation: explore-then-script

Produce a **reliable, runnable** script for a website flow the user describes. It has to work on the user's machine repeatedly, not once in a sandbox - so the workflow is *explore first, codify second*: record the human flow, replay it interactively to find the gotchas, then commit a script that already accounts for them and can prove its output is right.

If the user already has a working script and needs a tweak, skip this skill and edit the script. This is for **new** automation or **major rewrites**.

## Tools (two, on purpose)

- **Playwright codegen** records a real session into a `.spec.ts` with the selectors Playwright's engine settles on. Rarely the final script, always a truthful map of the flow.
- **browser-harness** (its own skill documents the CLI) attaches to the **operator's running Chrome** over CDP and runs Python on stdin. The operator is already logged in, so SSO, 2FA and Cloudflare are solved for free and the script never holds a credential. Default for anything behind a login.
- **Playwright** (`chromium.launchPersistentContext`) when the script needs a browser of its own: unattended/cron, headless, or an isolated profile with its own credentials. Same library as codegen, so one dependency covers record, explore and run.

Puppeteer and agent-browser are not used for new work. If the user has an existing script on one of them, maintain it in place rather than porting it.

## Workflow

### Phase 0: Capture intent

One short message, four questions:

1. **Site + flow** - URL and the end-to-end outcome ("log in to X, download last month's statement").
2. **Where the script lives** - absolute path. Propose a default from context; don't bikeshed.
3. **Whose browser session** - this decides the driver:
   - *The operator's* (they run it while at the desk; the site has SSO/2FA/bot-wall; no stored secrets wanted) → browser-harness.
   - *The script's own* (cron, headless, isolated creds) → Playwright persistent profile, and ask how credentials are read (varlock/1Password in personal repos, `.env`/env vars elsewhere - match the project).
4. **Self-healing on failure?** Ask outright, don't assume: *"when this fails later, should it open a `claude` agent in a herdr pane below to fix itself and retry?"* Yes → wire it per Phase 4. No → skip it entirely; the script still logs everything, a human just drives the fix. Only offer it when `HERDR_ENV=1`; outside herdr there is no pane to split, so don't raise it.

### Phase 1: Record with Playwright codegen

Tell the user to perform the whole flow once in the window that opens, including waits and text entry.

```bash
CODEGEN_OUT=$(mktemp -t codegen-XXXXXX.spec.ts)
npx playwright codegen --output "$CODEGEN_OUT" <URL>
# add --user-data-dir=<profile> to record against an already-logged-in profile
cat "$CODEGEN_OUT"
```

Install if needed: `npx -y playwright@latest install --with-deps chromium`.

Read the output for `getByRole`/`frameLocator`/URL patterns, iframes, downloads and waits.

**Also capture the request, not just the clicks.** Ask the user to keep DevTools → Network open while recording and, after the final action (export, download, table load), right-click the request that produced the data → *Copy as fetch*. Codegen shows *how a human gets the data*; the network entry shows *where the data actually comes from*. Phase 2 needs both. No DevTools, or you want the endpoints the recorded flow never called? *Obfuscated fields, undocumented endpoints* in the gotchas has two fallbacks.

### Phase 2: Pick the rung

**Find the credential first; it can rule out a rung.** Cookie: any tab, including one you open. `sessionStorage`: the operator's tab only. App memory: only code running in that tab. Check cookie names in DevTools → Application (`document.cookie` hides HttpOnly ones), `Object.keys(sessionStorage)`, then the headers on a call the app makes - before writing anything.

Lowest rung that holds:

1. **Replay the request.** If the data comes from one API call, reproduce that call and skip the UI. Same-origin `fetch()` evaluated inside the operator's tab (browser-harness `js()`) carries the session cookie and any per-request headers the SPA adds; `curl` with harvested cookies only when the site isn't behind TLS-fingerprint bot detection (Cloudflare 403s curl on perfectly good cookies - see *curl gets 403* first).
2. **Drive the UI.** Only when the request can't be replayed (cross-origin bearer token the app mints, download that only the page can trigger). Selectors structural - label, role, visible text, DOM shape - never framework class hashes.

Decide per source and write the decision down. Don't "try the cheap way and fall back": every rejected request is scored against the operator's live session.

### Phase 3: Explore interactively

Run the flow one or a few steps at a time, checking state between steps. When a click silently does nothing, **stop** - screenshot, inspect, understand - rather than stacking more actions on top.

- **Shape probe output in the page**, not in your context: a structure summary, a slice, a deduped list. Payloads run to tens of MB and a raw dump eats the context you need to finish.
- **Probe refusals now** - a date before the history, an id that doesn't exist, a scope you lack. A refusal is often HTTP 2xx with an empty or zeroed body, and each shape becomes a hard check in the final script.

When something does fail, look the symptom up instead of improvising: `rg -n '^## ' references/gotchas.md` lists every known symptom, then Read only the matching entry with `offset`/`limit`.

**browser-harness** (operator's Chrome):

```bash
browser-harness <<'PY'
tid = new_tab("https://example.com/")      # remember it - pin every later call
wait_for_load()
print(page_info())
print(js("document.title", target_id=tid))
capture_screenshot()
PY
```

The daemon has one globally "attached" tab that drifts when the operator clicks around, so pass `target_id=` on every read and never assume the current tab is yours. Its `js()` round-trip is capped at a few seconds: anything slower (an export endpoint, a slow SPA) is kicked off unawaited and polled - see *One call times out* in the gotchas.

**Playwright** (own profile): copy `templates/playwright-explore.mjs` into the project as `_explore.mjs` (leading `_` = scrap, must live inside the project so `node_modules` resolves), set the URL and profile dir, run it. It opens a headed browser and calls `page.pause()`, which drops you into the Inspector: step, record more, run selectors in its console. Anything the Inspector can't do, write a one-off `node -e` against the same profile.

**Bot detection is not a driver problem.** A block page or CAPTCHA that reproduces identically across tools has nothing to do with the tool. Levers, in order: use the operator's real Chrome (browser-harness); run headed (headless announces itself in the UA and can't be spoofed away); keep one warmed profile and reuse it - each fresh profile that gets blocked lowers the IP's reputation. Past that it's IP and account reputation: say so and ask.

### Phase 4: Write the final script

Start from the template for the path you took - `templates/harness-fetch-skeleton.py` or `templates/playwright-fetch-skeleton.mjs` - and read `references/final-script-style.md` in full. The properties that matter, in order:

1. **Follow-along logging.** An agent reading the captured log must know which step it reached, what URL/state the page was in, and why it failed - without re-running. Every step logs its label, the resulting URL/title, and what it matched. The Playwright template also writes a screenshot + DOM snapshot per step to `debug/<source>/`.
2. **Redacted.** Never log cookie/authorization/token values. Screenshots and DOM dumps of a logged-in session are secrets too: `debug/` is gitignored and not handed to anyone unscrubbed.
3. **Verifies its output.** Success is "N records in the requested range", not "a file exists". A valid-but-empty result is the dangerous failure - it passes every naive check and corrupts downstream. Assert the scope (which org/account/date window) *before* exporting; fail on zero rows unless the script declares empty legitimate for this source.
4. **Two failure classes.** *Needs a human* (signed out, missing permission) and *code is wrong* (endpoint changed, timeout) are distinguishable to the caller - a `LOGIN:` prefix, or distinct exit codes. Never work around missing auth in code.
5. **Docstring for the next agent.** Why this site is unusual - WAF, iframe, OTP - *and* what the data means: rolling windows, reporting lag, month-to-date only, params the endpoint ignores. Data semantics change what the script requests; DOM quirks only change how.
6. **Machine-readable result.** One JSON line on stdout (`{"source","file","rows",...}`); everything else on stderr.
7. **Timeouts under the transport.** No single driver round-trip may outlive the driver's own timeout. Kick off, then poll a page global.
8. **Shared-browser hygiene** (browser-harness): pin your tab, close only tabs you opened, never run two harness processes at once.
9. **Cleanup in `finally`.** Browser/context closed, downloads moved out of `~/Downloads`.
10. **Self-healing, if the operator asked for it in Phase 0.** Both templates already call `spawn-heal-pane.sh` from their failure path; to arm it, copy `scripts/spawn-heal-pane.sh` next to the final script (the templates look for it there and no-op when it is missing) and, in the harness template, set `SCRIPT_PATH`. Details and the invariants in `references/final-script-style.md`.

Then **run it cold once** - not from the explore session's state. Exploration state hides cookie banners, redirects and popups a warmed profile already dismissed. Report the success signal (rows, file path + size).

### Phase 5: Cleanup

Delete `_explore*` scrap unless wanted, close any browser you launched, remove tabs you parked in the operator's Chrome.

## Bundled resources

| File | Purpose |
|------|---------|
| `references/gotchas.md` | Symptom-indexed lookup table, driver-neutral. Not read whole. |
| `references/final-script-style.md` | Production-script conventions: logging, redaction, verification, failure classes, secrets |
| `templates/harness-fetch-skeleton.py` | browser-harness fetcher: pinned tab, in-page request replay with kick-and-poll, JSON envelope |
| `templates/playwright-fetch-skeleton.mjs` | Playwright persistent-profile fetcher with `step()`/`captureState()` debug capture and download handling |
| `templates/playwright-explore.mjs` | Headed persistent-profile launcher that stops in `page.pause()` for interactive exploration |
| `scripts/spawn-heal-pane.sh` | Opt-in self-heal: splits a `claude` healer pane below the failing run and briefs it to fix and retry by driving the pane above |
