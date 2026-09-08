#!/usr/bin/env node
//
// <SOURCE> fetcher - Playwright, persistent profile.
//
// Why this site is unusual:
//   - <WAF / login iframe / OTP / anti-bot / layout quirks found while exploring>
//
// What the data means:
//   - <rolling window? lag? params ignored? columns absent upstream?>
//
// Env (load via the project's convention - e.g. `await import("varlock/auto-load")`):
//   <SOURCE>_USER, <SOURCE>_PASS
// Optional:
//   <SOURCE>_DOWNLOAD_DIR   where to drop downloads (default ./downloads/<source>)
//   HEADLESS=1              only viable once the profile has logged in and the site
//                           doesn't gate on headless UA (most do - see gotchas.md)
//
// Exit 0 + one JSON line on stdout on success. Exit 2 with a LOGIN: message when a
// human must act; exit 1 for anything else. Debug artifacts under ./debug/<source>/.

import { chromium } from "playwright";
import { mkdirSync, writeFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const SOURCE = "<source>";
const ENV = SOURCE.toUpperCase().replace(/-/g, "_");

const USER = process.env[`${ENV}_USER`];
const PASS = process.env[`${ENV}_PASS`];
if (!USER || !PASS) {
  console.error(`[${SOURCE}] ${ENV}_USER / ${ENV}_PASS not set - check the project's env loading`);
  process.exit(1);
}

const DOWNLOAD_DIR = process.env[`${ENV}_DOWNLOAD_DIR`] ?? join(SCRIPT_DIR, "downloads", SOURCE);
const PROFILE_DIR = join(homedir(), ".local", "share", "browser-profiles", SOURCE);
const DEBUG_DIR = join(SCRIPT_DIR, "debug", SOURCE); // gitignore it: logged-in screenshots
const HEADLESS = process.env.HEADLESS === "1";
for (const d of [DOWNLOAD_DIR, PROFILE_DIR, DEBUG_DIR]) mkdirSync(d, { recursive: true });

// ---------- Logging: an agent must be able to follow the run from the log alone ----------
const log = (msg) => process.stderr.write(`[${SOURCE} ${new Date().toISOString()}] ${msg}\n`);
const redact = (s) => String(s).replace(/((?:cookie|authorization|x-api-key)\s*[:=]\s*)\S.*?(?='|$)/gi, "$1<redacted>");

let stepCounter = 0;
async function captureState(page, label) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const idx = String(++stepCounter).padStart(3, "0");
  const base = join(DEBUG_DIR, `${stamp}-${idx}-${label.replace(/\s+/g, "_")}`);
  const r = { idx, label, url: page.url() };
  try { await page.screenshot({ path: `${base}.png` }); r.png = `${base}.png`; } catch (e) { r.pngError = e.message; }
  try {
    const snap = await page.evaluate(() => {
      const vis = (el) => el.offsetParent !== null && el.getBoundingClientRect().width > 0;
      const sum = (el) => ({ tag: el.tagName.toLowerCase(), text: (el.innerText || "").trim().slice(0, 80),
        id: el.id || undefined, role: el.getAttribute("role") || undefined, aria: el.getAttribute("aria-label") || undefined });
      return {
        title: document.title,
        buttons: [...document.querySelectorAll("button, [role=button]")].filter(vis).slice(0, 30).map(sum),
        links: [...document.querySelectorAll("a")].filter(vis).slice(0, 30).map(sum),
        inputs: [...document.querySelectorAll("input, select, textarea")].filter(vis).slice(0, 20)
          .map((el) => ({ type: el.type, name: el.name, id: el.id, placeholder: el.placeholder })), // never el.value
        iframes: [...document.querySelectorAll("iframe")].map((f) => ({ id: f.id, src: f.src })),
      };
    });
    writeFileSync(`${base}.snap.json`, JSON.stringify(snap, null, 2));
    Object.assign(r, { snap: `${base}.snap.json`, title: snap.title, btns: snap.buttons.length, iframes: snap.iframes.length });
  } catch (e) { r.snapError = e.message; }
  log(`  state[${idx}]: ${label} | url=${r.url} | title=${JSON.stringify(r.title ?? "")} | btns=${r.btns ?? "?"} iframes=${r.iframes ?? "?"} | png=${r.png ?? "?"} snap=${r.snap ?? "?"}`);
  return r;
}

async function step(page, label, fn) {
  log(`step: ${label}`);
  try {
    const out = await fn();
    await captureState(page, `after-${label}`);
    return out;
  } catch (err) {
    log(`FAIL at step: ${label} (${redact(err.message)})`);
    await captureState(page, `fail-${label}`).catch(() => {});
    throw err;
  }
}

class LoginRequired extends Error {}

// ---------- Main ----------
const context = await chromium.launchPersistentContext(PROFILE_DIR, {
  headless: HEADLESS,
  viewport: { width: 1280, height: 800 },
  acceptDownloads: true,
  args: ["--disable-blink-features=AutomationControlled"],
});

let exitCode = 0;
try {
  log(`start: profile=${PROFILE_DIR} downloads=${DOWNLOAD_DIR} headless=${HEADLESS}`);
  const page = context.pages()[0] ?? (await context.newPage());

  await step(page, "open-home", () => page.goto("<HOME_URL>", { waitUntil: "domcontentloaded", timeout: 60_000 }));

  // ----- TODO: the flow you discovered. Each meaningful action in its own step(). -----
  //
  // Login (skip if the profile is already in):
  // await step(page, "login", async () => {
  //   if (!(await page.getByLabel("Username").isVisible())) return log("  already logged in");
  //   await page.getByLabel("Username").fill(USER);
  //   await page.getByLabel("Password").fill(PASS);
  //   await page.getByRole("button", { name: "Sign in" }).click();
  //   await page.waitForURL("**/dashboard", { timeout: 60_000 }).catch(() => {
  //     throw new LoginRequired("still on login page - OTP or captcha? open the profile headed and finish by hand");
  //   });
  // });
  //
  // Assert the SCOPE before exporting - the wrong org/account yields a valid, empty file:
  // await step(page, "assert-scope", async () => {
  //   const org = (await page.getByRole("button", { name: /organization/i }).innerText()).trim();
  //   if (org !== "<EXPECTED>") throw new Error(`wrong scope: ${org}`);
  // });
  //
  // Download - start waiting BEFORE the click:
  // const file = await step(page, "export", async () => {
  //   const dl = page.waitForEvent("download", { timeout: 120_000 });
  //   await page.getByRole("button", { name: "Export" }).click();
  //   const d = await dl;
  //   const dest = join(DOWNLOAD_DIR, d.suggestedFilename());
  //   await d.saveAs(dest);
  //   return dest;
  // });
  //
  // Verify the OUTPUT, not the exit: count rows, fail on zero unless this source
  // documents that empty is legitimate.
  // const rows = countRows(file);
  // if (rows === 0) throw new Error("export has 0 rows");
  // console.log(JSON.stringify({ source: SOURCE, file, rows, bytes: statSync(file).size }));
} catch (err) {
  if (err instanceof LoginRequired) { log(`LOGIN: ${err.message}`); exitCode = 2; }
  else { log(`FATAL: ${redact(err.message)}`); exitCode = 1; }
} finally {
  await context.close().catch(() => {});
}
process.exit(exitCode);
