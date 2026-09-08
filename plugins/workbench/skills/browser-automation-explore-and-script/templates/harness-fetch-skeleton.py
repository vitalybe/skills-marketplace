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
import json
import os
import tempfile
import time

ORIGIN = "https://example.com/"
REQUEST_URL = "https://example.com/api/export?..."   # copied from DevTools "Copy as fetch"

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
    raise SystemExit("LOGIN: <source>: tab was redirected off %s to %s - sign in there and retry" % (ORIGIN, _url))

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
    raise SystemExit("<source>: request did not respond within 120s")

_res = json.loads(js_("JSON.stringify(window.__job)"))
if _opened:  # only close what we opened
    try:
        close_tab(_tid)
    except Exception:
        pass
if _res.get("error"):
    if _res["error"] in ("HTTP 401", "HTTP 403"):
        raise SystemExit("LOGIN: <source>: %s - the session lacks access; sign in / request the role" % _res["error"])
    raise SystemExit("<source>: " + _res["error"])

rows = _res.get("data") or []
if not rows:  # empty is a failure unless THIS source documents that empty is legitimate
    raise SystemExit("<source>: request returned no rows")

out = os.environ.get("<SOURCE>_OUT") or os.path.join(tempfile.gettempdir(), "<source>.json")
with open(out, "w") as f:
    json.dump(rows, f)
# The only stdout line: the caller's contract.
print(json.dumps({"source": "<source>", "file": out, "rows": len(rows)}))
