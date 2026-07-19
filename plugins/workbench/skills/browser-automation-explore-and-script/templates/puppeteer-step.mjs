// Usage: node _explore-step.mjs '<json-action>'
//
// Connects to the long-running puppeteer browser (WS endpoint in
// /tmp/explore-puppeteer-ws), grabs the first non-blank page, and runs one of:
//
//   {"op":"url"}                       -> current URL + title
//   {"op":"eval","fn":"() => ..."}     -> run JS in the page, return value
//   {"op":"screenshot","path":"..."}   -> save screenshot (fullPage:bool optional)
//   {"op":"goto","url":"..."}          -> navigate
//   {"op":"click","selector":"..."}    -> click first matching CSS selector
//   {"op":"text","needle":"...","tag":"button"} -> click first <tag> whose
//                                        textContent contains needle (substring)
//   {"op":"snapshot"}                  -> compact list of visible buttons/links/iframes
//                                        with text + bounding box (good for picking selectors)
//
// Exit codes: 0 ok, 1 on error. Result is printed as JSON to stdout.
//
// For anything more complex (iframe walking, pointer-event chains,
// download wiring, network inspection), write a one-off
//   node -e 'import("puppeteer").then(async ({default: puppeteer}) => {...})'
// that connects via puppeteer.connect({browserWSEndpoint: ...}) and does
// exactly what you need. This step-runner is just the common case.

import puppeteer from "puppeteer";
import { readFileSync } from "node:fs";

const WS_FILE = "/tmp/explore-puppeteer-ws";
const wsEndpoint = readFileSync(WS_FILE, "utf8").trim();
const action = JSON.parse(process.argv[2] ?? '{"op":"url"}');

const browser = await puppeteer.connect({ browserWSEndpoint: wsEndpoint });
const pages = await browser.pages();
const page =
  pages.find((p) => !/^(about:|devtools:)/.test(p.url())) ?? pages[0];

const out = { op: action.op, url: page.url() };

try {
  switch (action.op) {
    case "url":
      out.title = await page.title();
      break;
    case "eval": {
      const fn = new Function(`return (${action.fn})()`);
      out.value = await page.evaluate(fn);
      break;
    }
    case "screenshot":
      await page.screenshot({ path: action.path, fullPage: !!action.fullPage });
      out.saved = action.path;
      break;
    case "goto":
      await page.goto(action.url, { waitUntil: action.waitUntil ?? "domcontentloaded", timeout: 60_000 });
      out.url = page.url();
      break;
    case "click":
      await page.click(action.selector);
      out.clicked = action.selector;
      break;
    case "text": {
      const tag = action.tag ?? "*";
      const handle = await page.evaluateHandle((tag, needle) => {
        const els = Array.from(document.querySelectorAll(tag));
        return els.find((el) =>
          (el.innerText || el.textContent || "").includes(needle) &&
          el.offsetParent !== null
        ) ?? null;
      }, tag, action.needle);
      const el = handle.asElement();
      if (!el) throw new Error(`no visible <${tag}> with text ${JSON.stringify(action.needle)}`);
      await el.click();
      out.clicked = { tag, needle: action.needle };
      break;
    }
    case "snapshot": {
      out.value = await page.evaluate(() => {
        const visible = (el) => el.offsetParent !== null && el.getBoundingClientRect().width > 0;
        const pick = (sel) =>
          Array.from(document.querySelectorAll(sel))
            .filter(visible)
            .slice(0, 80)
            .map((el) => {
              const r = el.getBoundingClientRect();
              return {
                tag: el.tagName.toLowerCase(),
                text: (el.innerText || el.textContent || "").trim().slice(0, 80),
                role: el.getAttribute("role"),
                id: el.id || undefined,
                name: el.getAttribute("name") || undefined,
                href: el.tagName === "A" ? el.getAttribute("href") : undefined,
                box: { x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) },
              };
            });
        return {
          buttons: pick("button, [role='button']"),
          links: pick("a"),
          iframes: Array.from(document.querySelectorAll("iframe")).map((f) => ({
            id: f.id, name: f.name, src: f.src,
          })),
        };
      });
      break;
    }
    default:
      throw new Error(`unknown op: ${action.op}`);
  }
  console.log(JSON.stringify(out, null, 2));
  await browser.disconnect();
  process.exit(0);
} catch (err) {
  out.error = err.message;
  console.log(JSON.stringify(out, null, 2));
  await browser.disconnect();
  process.exit(1);
}
