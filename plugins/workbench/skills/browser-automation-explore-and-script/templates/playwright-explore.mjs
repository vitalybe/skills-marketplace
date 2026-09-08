// Interactive exploration with a persistent profile.
//
// Copy into the PROJECT dir as _explore.mjs (node resolves "playwright" from the
// script's own directory, so /tmp won't work), set the two constants, run:
//
//   node _explore.mjs
//
// Opens a headed browser on START_URL and stops in page.pause(), which brings up the
// Playwright Inspector: step through actions, record more of the flow, try selectors
// in its console. Cookies/login persist in PROFILE_DIR between runs, so the final
// script can reuse the same profile. Close the Inspector to exit.
//
// Headed is not optional on detection-gated sites - headless announces itself.

import { chromium } from "playwright";
import { homedir } from "node:os";
import { join } from "node:path";

const START_URL = "https://example.com/";
const PROFILE_DIR = join(homedir(), ".local", "share", "browser-profiles", "<source>");

const context = await chromium.launchPersistentContext(PROFILE_DIR, {
  headless: false,
  viewport: { width: 1280, height: 800 },
  acceptDownloads: true,
  args: ["--disable-blink-features=AutomationControlled"],
});
const page = context.pages()[0] ?? (await context.newPage());
console.error(`[explore] profile=${PROFILE_DIR}`);
await page.goto(START_URL, { waitUntil: "domcontentloaded" });
await page.pause();
await context.close();
