# Puppeteer gotchas (symptom-indexed)

Real issues encountered driving Israeli-bank / Angular Material / SPA-with-session-id sites with puppeteer. When a flow misbehaves in unexpected ways, look here before fighting selectors.

## Page renders mobile layout even though I set the viewport

**Symptom:** `defaultViewport: { width: 1280, height: 800 }` in `puppeteer.launch()` is set, but the first tab renders at 800x600 (the puppeteer fallback when no viewport is set) and the page shows the mobile/small-screen layout - different DOM, mobile login buttons (`#ccLoginMobileBtn` instead of `#ccLoginDesktopBtn`), etc.

**Cause:** When you use `userDataDir` (persistent profile), puppeteer's `defaultViewport` is **not** applied to the first tab - Chrome opens it before puppeteer's viewport hook runs.

**Fix:** Call `await page.setViewport({ width: 1280, height: 800 })` explicitly on every page you get out of `browser.pages()` or `newPage()`, before you do anything else.

## CDP click succeeds but the UI doesn't change

**Symptom:** `await el.click()` (puppeteer's CDP click on an ElementHandle) returns successfully. The page logs no errors. But the UI clearly didn't react - tab didn't switch, button didn't activate, dropdown didn't open. Also fails if you try `el.evaluate((n) => n.click())` (the JS `.click()` method).

**Cause:** Angular Material components (`mat-tab-link`, `mat-button`, `mat-menu-item`, etc.) listen for the full pointer-event chain, not just `click`. Puppeteer's `el.click()` fires `mousemove/mousedown/mouseup/click` but **not** `pointerdown/pointerup`. Material checks `pointerdown` to commit the interaction. The DOM `.click()` method only fires `click`, which Material ignores entirely.

**Fix:** Dispatch the full chain from inside `frame.evaluate()`:

```js
await frame.evaluate(() => {
  const t = document.querySelector("[role=tab]"); // or whatever
  const r = t.getBoundingClientRect();
  const ev = (type) => new MouseEvent(type, {
    bubbles: true, cancelable: true, view: window,
    clientX: r.x + r.width / 2, clientY: r.y + r.height / 2, button: 0,
  });
  ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]
    .forEach((e) => t.dispatchEvent(ev(e)));
});
```

Playwright's `.click()` includes pointer events by default, so this isn't an issue there - it's a puppeteer-specific gap.

## Cross-origin iframes - same site, different URL pattern between pages

**Symptom:** Login flow works from the homepage but breaks when re-entering from a deep link. Your `page.frames().find((f) => /connect\.example\.com/.test(f.url()))` returns undefined.

**Cause:** Many sites serve the same login UI from different URLs depending on entry path. Example: `cal-online.co.il` mounts its login at `connect.cal-online.co.il/...` when opened from the homepage, but at `digital-web.cal-online.co.il/calconnect/...` when redirected from `/login`.

**Fix:** Match the iframe URL **generously**. Use a regex that captures both forms:

```js
const loginFrame = page.frames().find((f) =>
  /\/calconnect\/|connect\.example/.test(f.url())
);
```

If the iframe might take a moment to mount, poll for it:

```js
async function findFrame(predicate, timeoutMs = 15_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const f = page.frames().find(predicate);
    if (f) return f;
    await new Promise((r) => setTimeout(r, 250));
  }
  throw new Error("frame never appeared");
}
```

## page.reload() kills the session

**Symptom:** Logged in successfully, dashboard loaded at `https://app.example.com/dashboard?sid=abc-123-...`. You call `page.reload()` to refresh. Now you're redirected to `/login` and your session is dead.

**Cause:** Some SPAs put a session token in the URL (`?sid=...`). The server validates it once on first load, then expects subsequent requests to use cookies. Reload re-sends the URL as-is, but the sid is now considered "consumed" and the server 401s you.

**Fix:** Don't reload after login. Navigate via in-page clicks only. If you must change page, use `page.goto()` to a clean URL (no `sid`) and let the SPA route.

If you absolutely need a viewport change mid-flow, do it without reloading:

```js
// SAFE: just resize, no reload
await page.setViewport({ width: 1440, height: 900 });
// UNSAFE on session-id sites:
// await page.reload();
```

## Downloads don't work / land in the wrong place

**Symptom:** Click "Export" or "Download" - nothing happens in Node. No event fires. The file may end up in `~/Downloads/` instead of your configured directory.

**Cause:** Puppeteer doesn't have Playwright's `page.waitForEvent("download")`. You have to wire downloads through CDP yourself, and the default browser behavior is to use the OS download folder.

**Fix:** Per-page, configure download behavior and listen to `Browser.*` events:

```js
const cdp = await page.createCDPSession();
await cdp.send("Browser.setDownloadBehavior", {
  behavior: "allow",
  downloadPath: DOWNLOAD_DIR,
  eventsEnabled: true,
});

cdp.on("Browser.downloadWillBegin", (e) => {
  console.log(`download begin: ${e.suggestedFilename} (guid=${e.guid})`);
});
cdp.on("Browser.downloadProgress", (e) => {
  if (e.state === "completed") console.log(`download complete: guid=${e.guid}`);
});

// Then trigger the click. To wait for completion, either await a Promise
// resolved from the "completed" event, or poll DOWNLOAD_DIR for new files:
const before = new Set(fs.readdirSync(DOWNLOAD_DIR));
await page.click("button.export");
// ... poll for new file ...
```

Polling-the-directory is the most robust approach because some sites trigger the download from a worker or async fetch that doesn't fire `downloadWillBegin` cleanly.

## Puppeteer's bundled Chromium download is corrupt

**Symptom:** `pnpm add puppeteer` succeeds but the post-install fails to extract the Chrome zip ("End-of-central-directory signature not found" / "cannot find zipfile directory").

**Fix:** Skip the download and use an existing Chrome. agent-browser ships one at `~/.agent-browser/browsers/chrome-*/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing`. Pass it via `executablePath`:

```js
const browser = await puppeteer.launch({
  executablePath: "/Users/<you>/.agent-browser/browsers/chrome-148.0.7778.167/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing",
  // ... other options
});
```

On Linux, `/usr/bin/google-chrome` or `/usr/bin/chromium` work.

## Script in tmp/ can't find puppeteer

**Symptom:** `node /tmp/explore-launcher.mjs` fails with `Cannot find package 'puppeteer'`.

**Cause:** Node resolves `import "puppeteer"` from the script's directory upward, not from `cwd`. `cd /project && node /tmp/script.mjs` looks in `/tmp/node_modules`, not `/project/node_modules`.

**Fix:** Put the explore scripts inside the project directory (where `node_modules/` lives). The leading `_` prefix (`_explore-launcher.mjs`) keeps them out of the way without hiding them from `ls`.

## 1Password CLI authorization timeout mid-session

**Symptom:** A varlock-loaded script that worked five minutes ago now errors with "1Password CLI error - error initializing client: authorization timeout".

**Cause:** `op` caches its biometric unlock for a limited window (configurable in 1Password's settings, usually 5-30 min). After expiry, the next CLI call needs a fresh Touch ID prompt.

**Fix:** Tell the user to unlock 1Password (Touch ID or `op signin`) and rerun. No code workaround - this is a user-action step.

## Click "Export" but no menu / no download

**Symptom:** You found a visible export button by aria-label, clicked it, nothing visible happens.

**Cause:** Sometimes "export" is a `<span>` not a `<button>` - the actual click target is a parent element with a click handler. Or it triggers a hidden form submit that races with your script.

**Fix:** Climb to the nearest clickable ancestor, and dispatch the full pointer chain:

```js
await page.evaluate(() => {
  const span = document.querySelector("span.export[aria-label=Export]");
  const clickable = span.closest("button, a, [role=button]") || span;
  const r = clickable.getBoundingClientRect();
  const ev = (t) => new MouseEvent(t, {
    bubbles: true, cancelable: true, view: window,
    clientX: r.x + r.width / 2, clientY: r.y + r.height / 2, button: 0,
  });
  ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]
    .forEach((e) => clickable.dispatchEvent(ev(e)));
});
```

Also check the actual aria-label text character-by-character - Hebrew "ייצוא" (double-yod) and "יצוא" (single-yod) look identical to a Latin-script reader but are distinct strings.
