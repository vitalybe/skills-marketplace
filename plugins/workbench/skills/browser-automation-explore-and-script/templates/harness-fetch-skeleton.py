# browser-harness fetcher for the "<source>" source.
#
#   <SOURCE>_OUT=/tmp/<source>.json cat fetch_<source>.py | browser-harness
#
# Why this site is unusual:
#   - <WAF / SSO / iframe / deep-link-404 / class-hash quirks found while exploring>
#
# What the data means:
#   - <rolling window? reporting lag? month-to-date only? params the endpoint ignores?>
#
# Runs inside the operator's own Chrome (remote debugging enabled), so it holds no
# credentials: the request is replayed same-origin with the session already there.
#
# Env:
#   <SOURCE>_OUT=<path>   where to write the result (default: temp dir)
#   SELFHEAL=0            disable the self-heal pane (see fail() below)
import json
import os
import subprocess
import sys
import tempfile
import time

ORIGIN = "https://example.com/"
REQUEST_URL = "https://example.com/api/export?..."   # copied from DevTools "Copy as fetch"

# This file is piped into browser-harness on stdin, so there is no __file__ to
# read - spell out where it lives, so the healer can find and edit it.
SCRIPT_PATH = "<absolute path to this file>"
RUN_LOG = os.environ.get("<SOURCE>_LOG") or os.path.join(tempfile.gettempdir(), "<source>.run.log")


def log(msg):
    """stderr for the operator, one file for whoever debugs this later."""
    line = "[<source> %s] %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S"), msg)
    sys.stderr.write(line)
    try:
        with open(RUN_LOG, "a") as fh:
            fh.write(line)
    except OSError:
        pass


def fail(msg, login=False):
    """Exit on a failure, and hand the code-is-wrong class to a self-heal agent.

    login=True means a human must act (signed out, missing role). No healer for
    those: an agent must never script around missing auth. Everything else is a
    code bug, so a `claude` agent is spawned in a herdr pane below this one to fix
    the script and retry it by driving this pane. Opt out with SELFHEAL=0; a no-op
    outside herdr or when the helper is not next to the script.
    """
    log(("LOGIN: " if login else "FATAL: ") + msg)
    helper = os.path.join(os.path.dirname(SCRIPT_PATH), "spawn-heal-pane.sh")
    if not login and os.environ.get("SELFHEAL") != "0" and os.path.exists(helper):
        subprocess.run(["bash", helper,
                        "--script", SCRIPT_PATH,
                        "--cmd", "cat %s | browser-harness" % SCRIPT_PATH,
                        "--log", RUN_LOG,
                        "--error", msg], check=False)
    raise SystemExit(("LOGIN: " if login else "") + "<source>: " + msg)

# A tab is only needed for its ORIGIN. Reuse one the operator already has open on
# this host rather than piling up new ones; open our own only if none exists.
_tid, _opened = None, False
for _tab in list_tabs():
    if (_tab.get("url") or "").startswith(ORIGIN):
        _tid = _tab.get("target_id") or _tab.get("targetId")
        break
if _tid is None:
    _tid = new_tab(ORIGIN)
    _opened = True


def js_(expr):
    """Every read pinned to OUR tab - the daemon's current tab drifts with the operator."""
    return js(expr, target_id=_tid)


wait_for_load()
_url = js_("location.href") or ""
if not _url.startswith(ORIGIN):
    fail("tab was redirected off %s to %s - sign in there and retry" % (ORIGIN, _url), login=True)

# Kick the request off unawaited and poll: one js() round-trip must stay under the
# harness's IPC timeout (~5s), and exports routinely take longer. The trailing
# 'kicked' literal is load-bearing - js() awaits the LAST expression, and that must
# not be the promise.
_kick = """(() => {
window.__job = {done: false};
fetch(%s, {credentials: 'include', headers: {accept: 'application/json'}}).then(async res => {
  if (!res.ok) { window.__job = {done: true, error: 'HTTP ' + res.status}; return; }
  const body = await res.json();
  // Filter/shape HERE so only what you need crosses the wire.
  window.__job = {done: true, data: body};
}).catch(e => { window.__job = {done: true, error: String(e)}; });
return 'kicked';
})()""" % json.dumps(REQUEST_URL)

js_(_kick)
for _ in range(60):  # 60 * 2s = 2 min ceiling
    time.sleep(2)
    if js_("!!(window.__job && window.__job.done)"):
        break
else:
    fail("request did not respond within 120s")

_res = json.loads(js_("JSON.stringify(window.__job)"))
if _opened:  # only close what we opened
    try:
        close_tab(_tid)
    except Exception:
        pass
if _res.get("error"):
    if _res["error"] in ("HTTP 401", "HTTP 403"):
        fail("%s - the session lacks access; sign in / request the role" % _res["error"], login=True)
    fail(_res["error"])

rows = _res.get("data") or []
if not rows:  # empty is a failure unless THIS source documents that empty is legitimate
    fail("request returned no rows")

out = os.environ.get("<SOURCE>_OUT") or os.path.join(tempfile.gettempdir(), "<source>.json")
with open(out, "w") as f:
    json.dump(rows, f)
# The only stdout line: the caller's contract.
print(json.dumps({"source": "<source>", "file": out, "rows": len(rows)}))
