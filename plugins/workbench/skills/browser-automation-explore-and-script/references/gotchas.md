# Gotchas (symptom-indexed)

Real failures from past sessions, organised by what you see. Grep here before fighting selectors.

## One call times out even though the page is fine

**Symptom:** `js()` / `evaluate()` fails with "timed out" on a fetch that finishes in 6s when you watch it in DevTools.

**Cause:** the driver's transport has its own ceiling (browser-harness's IPC read is ~5s) and your single round-trip outlived it.

**Fix:** kick-and-poll. Start the work unawaited, park the result on `window`, poll with sub-second reads:

```js
// kick (note the trailing literal: with awaitPromise the LAST expression is what
// gets awaited - end on a string, not on the promise you're trying not to await)
window.__job = {done: false};
fetch(url, {credentials: 'include'}).then(r => r.json())
  .then(d => { window.__job = {done: true, data: d}; })
  .catch(e => { window.__job = {done: true, error: String(e)}; });
'kicked'
```

then poll `!!(window.__job && window.__job.done)` every ~2s up to your real budget, and read the result in a separate call.

## The next call after a navigation times out

**Symptom:** you navigated the tab straight to a JSON/CSV URL; the *following* evaluate times out.

**Cause:** Chrome lays a multi-MB text response out as a document and blocks the renderer for seconds.

**Fix:** never navigate to the data URL. `fetch()` it from a page on the same origin and keep the payload in JS; only the filtered result crosses the wire.

## Reads come back from the wrong page

**Symptom:** `document.title` or a selector returns something from a completely different site; the flow works on one run and reads garbage on the next.

**Cause:** a driver with a single "current tab" (browser-harness's daemon) follows whatever the operator - or another script - focused last.

**Fix:** capture the target id when you open your tab and pass it on every call (`js(expr, target_id=tid)`, or re-`switch_tab(tid)` before each read). Close only tabs you opened; a tab you borrowed belongs to the operator.

## Same probe, different answer each run

**Symptom:** several SPAs probed concurrently report "logged in" on one run and "signed out" on the next.

**Cause:** reading a SPA while it's still booting returns whatever the shell has rendered so far.

**Fix:** serialize. Open one tab, wait, read, then the next. Parallelism that flip-flops is slower than sequential.

## curl gets 403 with cookies that work in the browser

**Symptom:** cookies harvested from Chrome, request replayed with `curl` → 403, even fresh ones.

**Cause:** the site (Cloudflare and friends) scores the TLS/JA3 fingerprint, not the cookie.

**Fix:** replay the request *inside* the browser via same-origin `fetch()` (browser-harness `js()`). Don't retry curl "to see" - every rejected request counts against the live session's reputation.

## Cookies alone are rejected, but the SPA's own calls succeed

**Symptom:** same URL, same cookies, 403 `not_authorized`; the app's XHR to that URL is 200.

**Cause:** the SPA adds per-request headers (tenant/user/workspace ids, CSRF) you didn't send.

**Fix:** copy the request from DevTools as fetch and diff headers. Recover ids from where the app keeps them (localStorage keys, a bootstrap JSON) rather than hardcoding.

## Export succeeds with zero rows

**Symptom:** valid CSV, header only, script exits 0, dashboard silently loses a month.

**Cause:** the export ran in the wrong scope - wrong org/account/project, a date window the endpoint ignores, or the app's data horizon lags the calendar.

**Fix:** assert the scope in the DOM before exporting and fail loudly if it isn't what you expect. Treat zero rows as failure unless the source declares empty legitimate. If the endpoint ignores your date params (rolling window), filter client-side and document the limit.

## Permission wall that isn't one

**Symptom:** the page shows "required permission: X" or drops a nav link; a second later it renders fine.

**Cause:** the SPA paints the failure state while it resolves org context.

**Fix:** only trust a negative after the positive signal has been polled for its whole budget (e.g. 20s looking for the link). Report the verbatim permission sentence when it *is* real - it tells the operator exactly which role to request.

## Deep link renders "Page not found"

**Symptom:** the URL you copied from the address bar 404s when loaded directly.

**Cause:** the route only resolves after the SPA has booted with context.

**Fix:** enter via a route that renders cold (billing overview, home), then click the in-app link - a client-side transition.

## Click succeeds, UI doesn't change

**Symptom:** the click returns without error; tab didn't switch, menu didn't open.

**Cause:** custom components (Angular Material, web components) listen for the full pointer chain; `el.click()` from `evaluate` only fires `click`.

**Fix:** use a real input path - Playwright's locator `.click()` or browser-harness `click_at_xy()` both dispatch pointer events at the compositor. If you must synthesise from JS, fire `pointerdown, mousedown, pointerup, mouseup, click` in order at the element's centre. And check you're hitting the clickable ancestor: "Export" is often a `<span>` inside the real `<button>` - `el.closest("button, a, [role=button]")`.

## Selector worked last month, empty now

**Symptom:** `._6UBrL` / `button[aria-haspopup=menu]` returns nothing after a deploy.

**Cause:** CSS-module hashes and incidental attributes change on every build.

**Fix:** locate structurally - label, role, visible text, or shape ("the control whose text is an avatar letter plus the name"). Keep the old selector as a fallback, log which one matched.

## Reload logs you out

**Symptom:** `?sid=...` in the URL after login; `reload()` bounces to `/login`.

**Cause:** the session id is validated once on first load, then expected via cookie; re-sending it 401s.

**Fix:** never reload after login. Navigate with in-page clicks, or `goto` a clean URL without the sid.

## Login iframe URL differs by entry path

**Symptom:** frame lookup finds `connect.example.com/...` from the homepage but nothing from `/login`.

**Fix:** match generously (`/connect\.example|\/calconnect\//`) and poll for the frame to mount. Playwright's `frameLocator` handles cross-origin frames; browser-harness coordinate clicks pass through them.

## Download lands in ~/Downloads or never fires

**Playwright:** `const dl = page.waitForEvent('download'); await click(); await (await dl).saveAs(dest)`. Start waiting *before* the click.

**browser-harness:** Chrome downloads to the operator's `~/Downloads`. Snapshot the directory before the click, poll for a new file matching the expected name pattern with no `.crdownload` sibling, copy it out, delete the original.

Polling the directory is the robust fallback everywhere - some sites trigger downloads from a worker that fires no event.

## Headless is blocked, headed works

Headless Chrome's UA literally says `HeadlessChrome/`; `--user-agent` downgrades a hard block to a CAPTCHA because `screen` stays 800x600. No header-level fix. Run headed (hide the window at the OS level if it's in the way), or use the operator's real Chrome.

## Fresh profile fails, old profile works

On detection-gated sites a fresh profile is itself a signal. Before touching code, re-run the unchanged script on the known-good profile: passes → the profile was flagged, not the script. Profiles are consumable; warm one and keep it.

## 1Password CLI "authorization timeout" mid-run

`op`'s biometric unlock expires. Ask the user to unlock (Touch ID / `op signin`) and rerun. Not a code problem.
