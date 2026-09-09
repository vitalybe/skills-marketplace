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

**Fix:** copy the request from DevTools as fetch and diff headers. Recover ids from where the app keeps them (localStorage keys, a bootstrap JSON) rather than hardcoding. Diff on a *failing* call, not a passing one: anything you generated yourself (a random id, a timestamp) is the suspect, because the server may validate it as a pair with the token - a credential you read off live traffic can still 401 when sent with your own nonce.

## The session can't be reached from a tab you opened

**Symptom:** the operator is signed in; your new tab on the same origin gets 401 or lands on the login page.

**Cause:** a cookie goes out from any tab. `sessionStorage` is per tab and a CDP-opened tab starts empty, so it authenticates only if the app re-mints from a cookie on load - usual for a bearer from silent SSO, impossible behind a password form. A token living only in the app's memory needs code running in *that* tab: the framework's state, or a wrapper on `fetch`/XHR.

**Fix:** per-tab or in-memory means borrowing the operator's tab, and "no tab open" is a `LOGIN:` condition.

## Minting your own session logs the operator out

**Symptom:** your login/handshake call returns a working credential; the operator's app bounces to a login or home screen, and every credential you mint afterwards is rejected.

**Cause:** one session per user. The server evicts the previous one, which was theirs.

**Fix:** never mint on an app the operator is using; borrow the credential the running app holds. If you already evicted them, re-navigate to the app's entry URL so its handshake re-runs off the outer session, and say so in the report.

## Auth failure with no HTTP status

**Symptom:** `TypeError: Failed to fetch`, status 0, on a same-origin URL - while an unrelated call from the same page returns 200.

**Cause:** some gateways reset the connection on a missing or malformed header, or on the wrong method, instead of answering 401. At the status level, unauthenticated is indistinguishable from an outage.

**Fix:** run a control call to a known-good endpoint from the same page first, to prove the page isn't the problem. Then key auth detection off the response *body* - an exception type, an error code - rather than off the status.

## You are not the only one patching the page

**Symptom:** your `fetch` / XHR wrapper stops firing after a few seconds, or the page's own calls break while yours is installed.

**Cause:** analytics and session-replay libraries wrap the same globals and re-arm themselves, silently dropping any patch layered on top.

**Fix:** snapshot `String(window.fetch)` / `XMLHttpRequest.prototype.open` first, keep your wrapper installed only as long as it takes to read the value, restore the originals through a closure the page holds in `finally`, and check they match the snapshot.

## Export succeeds with zero rows

**Symptom:** valid CSV, header only, script exits 0, dashboard silently loses a month.

**Cause:** the export ran in the wrong scope - wrong org/account/project, a date window the endpoint ignores, or the app's data horizon lags the calendar.

**Fix:** assert the scope in the DOM before exporting and fail loudly if it isn't what you expect. Treat zero rows as failure unless the source declares empty legitimate. If the endpoint ignores your date params (rolling window), filter client-side and document the limit.

## The API's "no" is an HTTP 200

**Symptom:** a request for a scope or a date the provider doesn't have returns success with nothing useful: an empty array, a bare `null`, a total of 0, a payload missing the data key entirely, or a 2xx that isn't 200.

**Cause:** the provider models "nothing for that" as success, and the body shape differs per endpoint.

**Fix:** encode each shape you find as its own hard failure that names what was refused. An echoed default - today's date where you asked for another - means "nothing for that", not "here is that".

## Obfuscated fields, undocumented endpoints

**Symptom:** responses like `{"a":"0","bd":207,"bf":22414.25}`, no endpoint list, and two similar fields where you can't tell which one the UI actually shows.

**Fix:** read the app's bundle. It is static, greppable, and costs the live session nothing.

- `rg -o 'api/[\w./-]+' *.js | sort -u` over every chunk, using the path prefix you saw in DevTools. Surfaces endpoints the recorded flow never hit; misses paths assembled at runtime.
- Single-letter response fields usually have a mapping table in the bundle (`{a:"Name", b:"Value"}`). Copy it into the script.
- When several fields look plausible, the function that computes the number rendered on screen settles which is authoritative.

For URLs with no patching: `performance.setResourceTimingBufferSize(5000); performance.clearResourceTimings()`, operator clicks, then `performance.getEntriesByType('resource')` gives name, `initiatorType`, `responseStatus` (same-origin only, no headers). Raise the buffer first: it defaults to 250 entries, and some apps clear it themselves.

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
