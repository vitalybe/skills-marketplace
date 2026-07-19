// Long-running puppeteer launcher for semi-interactive exploration.
//
// Launches a headed Chrome (so you can watch what's happening) with a
// persistent user-data-dir (so cookies/login survive between runs),
// opens the target site, then prints the CDP WS endpoint to a tmp file
// so subsequent step scripts can puppeteer.connect() to the same browser.
//
// Stays alive until you close the browser window or Ctrl-C this process.
//
// EDIT THESE FOUR CONSTANTS BEFORE RUNNING:
//   START_URL    - the page to open
//   PROFILE_DIR  - where Chrome's user-data-dir lives (per-site is good)
//   CHROME_BIN   - path to a Chrome/Chromium binary
//   WS_FILE      - where to write the WS endpoint (default is fine)

import puppeteer from "puppeteer";
import { homedir } from "node:os";
import { join } from "node:path";
import { writeFileSync } from "node:fs";

const START_URL = "https://example.com/";
const PROFILE_DIR = join(homedir(), ".local", "share", "explore-profiles", "example");
// On macOS, agent-browser ships a Chrome you can reuse (no separate download):
//   /Users/<you>/.agent-browser/browsers/chrome-*/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing
// On Linux: /usr/bin/google-chrome or wherever Chrome is installed.
// Leave undefined to let puppeteer use its bundled Chromium.
const CHROME_BIN = undefined;
const WS_FILE = "/tmp/explore-puppeteer-ws";

const browser = await puppeteer.launch({
  headless: false,
  ...(CHROME_BIN ? { executablePath: CHROME_BIN } : {}),
  userDataDir: PROFILE_DIR,
  // NOTE: This defaultViewport is IGNORED for the first tab when using a
  // persistent userDataDir. The step scripts should setViewport() per-page.
  defaultViewport: { width: 1280, height: 800 },
  args: [
    "--disable-blink-features=AutomationControlled",
  ],
});

const wsEndpoint = browser.wsEndpoint();
writeFileSync(WS_FILE, wsEndpoint);
console.log(`[launcher] ws=${wsEndpoint}`);
console.log(`[launcher] profile=${PROFILE_DIR}`);

const pages = await browser.pages();
const page = pages[0] ?? (await browser.newPage());
// setViewport here in case the first persistent-profile tab opens at 800x600.
await page.setViewport({ width: 1280, height: 800 });
await page.goto(START_URL, { waitUntil: "domcontentloaded", timeout: 60_000 });
console.log(`[launcher] loaded: ${page.url()}`);

browser.on("disconnected", () => {
  console.log("[launcher] browser disconnected, exiting");
  process.exit(0);
});

// Heartbeat so you know it's still alive in the terminal.
setInterval(() => {
  console.log(`[launcher] alive at ${new Date().toISOString()}, url=${page.url()}`);
}, 30_000);
