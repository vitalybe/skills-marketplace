#!/usr/bin/env node
//
// <SOURCE> account fetcher.
//
// Why this is unusual:
//   - <document any WAF, iframe, OTP, anti-bot, or layout quirks the
//     explore phase uncovered. The next agent who has to fix this after
//     the site redesigns will thank you.>
//
// Env (loaded via varlock from ./.env.schema):
//   ACCOUNT_<SOURCE>_USER  username
//   ACCOUNT_<SOURCE>_PASS  password
//
// Optional env:
//   HEADED=1                  show the browser window (default: 1)
//   FINANCE_HEADLESS=1        force headless (only viable after first login)
//   FINANCE_DOWNLOAD_DIR      where to drop downloads (defaults under ./downloads/<source>)
//
// Exits 0 on success; non-zero otherwise with debug artifacts under ./debug/<source>/.

import puppeteer from "puppeteer";
import { existsSync, mkdirSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const SOURCE = "<source>"; // e.g. "cal", "max" — used in paths and log prefix

{
  const originalCwd = process.cwd();
  process.chdir(SCRIPT_DIR);
  await import("varlock/auto-load");
  process.chdir(originalCwd);
}

const USER = process.env[`ACCOUNT_${SOURCE.toUpperCase()}_USER`];
const PASS = process.env[`ACCOUNT_${SOURCE.toUpperCase()}_PASS`];
if (!USER || !PASS) {
  console.error(`[finance-${SOURCE}-account] varlock did not populate creds - check .env.schema`);
  process.exit(1);
}

const DOWNLOAD_DIR = process.env.FINANCE_DOWNLOAD_DIR ?? join(SCRIPT_DIR, "downloads", SOURCE);
const PROFILE_DIR = join(homedir(), ".local", "share", "finance-importer", `${SOURCE}-profile`);
const DEBUG_DIR = join(SCRIPT_DIR, "debug", SOURCE);
const HEADED = process.env.FINANCE_HEADLESS === "1" ? false : true;

mkdirSync(DOWNLOAD_DIR, { recursive: true });
mkdirSync(PROFILE_DIR, { recursive: true });
mkdirSync(DEBUG_DIR, { recursive: true });

// ---------- Logging ----------
//
// Every interesting event goes to stderr with an ISO timestamp and the script's
// name as a prefix. The principle: a future agent looking at the captured log
// must be able to tell EXACTLY where the script got to and what state the page
// was in - without re-running the script. So we log:
//   - every "step" boundary (entering + exiting)
//   - the URL after every navigation / waited transition
//   - a compact "what's visible right now" snapshot at decision points
//   - the actual selector / text / id we matched (not just "clicked button")
//
// Snapshots and screenshots also go to ./debug/<source>/<iso>-<label>.{png,snap.json}
// on every step (not only on failure) so the log can reference them.

const LOG_PREFIX = `[finance-${SOURCE}-account`;
const log = (msg) => process.stderr.write(`${LOG_PREFIX} ${new Date().toISOString()}] ${msg}\n`);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let stepCounter = 0;
async function captureState(page, label) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const idx = String(++stepCounter).padStart(3, "0");
  const base = join(DEBUG_DIR, `${stamp}-${idx}-${label.replace(/\s+/g, "_")}`);
  const result = { idx, label, url: page.url() };
  try {
    await page.screenshot({ path: `${base}.png`, fullPage: false });
    result.screenshot = `${base}.png`;
  } catch (e) { result.screenshotError = e.message; }
  try {
    const snap = await page.evaluate(() => {
      const visible = (el) => el.offsetParent !== null && el.getBoundingClientRect().width > 0;
      const summarize = (el) => {
        const r = el.getBoundingClientRect();
        return {
          tag: el.tagName.toLowerCase(),
          text: (el.innerText || el.textContent || "").trim().slice(0, 80),
          id: el.id || undefined,
          role: el.getAttribute("role") || undefined,
          ariaLabel: el.getAttribute("aria-label") || undefined,
          x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height),
        };
      };
      return {
        title: document.title,
        innerW: window.innerWidth, innerH: window.innerHeight,
        buttons: Array.from(document.querySelectorAll("button, [role='button']")).filter(visible).slice(0, 30).map(summarize),
        links: Array.from(document.querySelectorAll("a")).filter(visible).slice(0, 30).map(summarize),
        inputs: Array.from(document.querySelectorAll("input, textarea, select")).filter(visible).slice(0, 20).map((el) => ({
          type: el.type, name: el.name, id: el.id, placeholder: el.placeholder,
          formControl: el.getAttribute("formcontrolname"), ariaLabel: el.getAttribute("aria-label"),
        })),
        iframes: Array.from(document.querySelectorAll("iframe")).map((f) => ({ id: f.id, src: f.src, w: f.offsetWidth, h: f.offsetHeight })),
      };
    });
    writeFileSync(`${base}.snap.json`, JSON.stringify(snap, null, 2));
    result.snapshot = `${base}.snap.json`;
    result.title = snap.title;
    result.viewport = { w: snap.innerW, h: snap.innerH };
    result.iframeCount = snap.iframes.length;
    result.buttonCount = snap.buttons.length;
  } catch (e) { result.snapshotError = e.message; }
  log(`  state[${idx}]: ${label} | url=${result.url} | title=${JSON.stringify(result.title ?? "")} | btns=${result.buttonCount ?? "?"} iframes=${result.iframeCount ?? "?"} | png=${result.screenshot ?? "?"} snap=${result.snapshot ?? "?"}`);
  return result;
}

async function step(page, label, fn) {
  log(`step: ${label}`);
  try {
    const result = await fn();
    await captureState(page, `after-${label}`);
    return result;
  } catch (err) {
    log(`FAIL at step: ${label} (${err.message})`);
    await captureState(page, `fail-${label}`).catch(() => {});
    throw err;
  }
}

// ---------- Main flow ----------

const browser = await puppeteer.launch({
  headless: !HEADED,
  userDataDir: PROFILE_DIR,
  defaultViewport: { width: 1280, height: 800 },
  args: ["--disable-blink-features=AutomationControlled"],
});

let exitCode = 0;
try {
  log(`start: profile=${PROFILE_DIR} downloads=${DOWNLOAD_DIR}`);
  const pages = await browser.pages();
  const page = pages[0] ?? (await browser.newPage());
  // CRITICAL on persistent-profile: setViewport per-page, otherwise the first
  // tab opens at 800x600 and many sites render mobile layouts.
  await page.setViewport({ width: 1280, height: 800 });

  // Wire downloads. Puppeteer has no waitForEvent("download") - use CDP.
  const cdp = await page.createCDPSession();
  await cdp.send("Browser.setDownloadBehavior", {
    behavior: "allow", downloadPath: DOWNLOAD_DIR, eventsEnabled: true,
  });
  cdp.on("Browser.downloadWillBegin", (e) => log(`  download begin: ${e.suggestedFilename}`));
  cdp.on("Browser.downloadProgress", (e) => {
    if (e.state !== "inProgress") log(`  download ${e.state}: received=${e.receivedBytes}/${e.totalBytes}`);
  });

  await step(page, "open-home", async () => {
    await page.goto("<HOME_URL>", { waitUntil: "domcontentloaded", timeout: 60_000 });
  });

  // ----- TODO: insert the flow you discovered during exploration. -----
  // Wrap each meaningful action in `await step(page, "<label>", async () => { ... })`
  // so the log shows where you got + a snapshot of the resulting page.
  //
  // Example patterns (delete the ones you don't need):
  //
  // // Click an Angular Material tab (CDP click won't switch it - need pointer chain)
  // await step(page, "switch-to-username-tab", async () => {
  //   const frame = page.frames().find((f) => /login-iframe-pattern/.test(f.url()));
  //   await frame.evaluate(() => {
  //     const t = Array.from(document.querySelectorAll("[role=tab]"))
  //       .find((el) => (el.textContent || "").trim() === "Username");
  //     const r = t.getBoundingClientRect();
  //     const ev = (type) => new MouseEvent(type, { bubbles: true, cancelable: true, view: window, clientX: r.x+r.width/2, clientY: r.y+r.height/2, button: 0 });
  //     ["pointerdown","mousedown","pointerup","mouseup","click"].forEach((e) => t.dispatchEvent(ev(e)));
  //   });
  //   await sleep(1500);
  // });

  // // Fill an input inside a frame
  // await step(page, "fill-credentials", async () => {
  //   const frame = page.frames().find((f) => /login-iframe-pattern/.test(f.url()));
  //   const u = await frame.$("input[formcontrolname=userName]");
  //   const p = await frame.$("input[formcontrolname=password]");
  //   await u.click({ clickCount: 3 }); await u.type(USER, { delay: 30 });
  //   await p.click({ clickCount: 3 }); await p.type(PASS, { delay: 30 });
  // });

  // // Wait for a download triggered by a click
  // const before = new Set(readdirSync(DOWNLOAD_DIR));
  // await step(page, "click-export", async () => { /* ... click the export button ... */ });
  // const downloaded = await waitForDownload(before, 120);
  // log(`done: ${downloaded.path} (${downloaded.size} bytes)`);

} catch (err) {
  log(`FATAL: ${err.message}`);
  exitCode = 1;
} finally {
  await browser.close().catch(() => {});
}
process.exit(exitCode);

// ---------- Helpers ----------

async function waitForDownload(beforeFiles, timeoutSec = 120) {
  for (let i = 0; i < timeoutSec; i++) {
    const files = readdirSync(DOWNLOAD_DIR);
    const candidate = files
      .filter((f) => !beforeFiles.has(f) && !/\.crdownload$/i.test(f))
      .map((f) => ({ f, m: statSync(join(DOWNLOAD_DIR, f)).mtimeMs }))
      .sort((a, b) => b.m - a.m)[0]?.f;
    const partial = files.find((f) => /\.crdownload$/i.test(f));
    if (candidate && !partial) {
      const full = join(DOWNLOAD_DIR, candidate);
      return { path: full, size: statSync(full).size };
    }
    if (i % 5 === 0) log(`  ${partial ? `download in progress: ${partial}` : "no new file yet"} (${i}s/${timeoutSec}s)`);
    await sleep(1000);
  }
  throw new Error(`no new file appeared in ${DOWNLOAD_DIR} after ${timeoutSec}s`);
}
