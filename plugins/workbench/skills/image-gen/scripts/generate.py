#!/usr/bin/env python3
"""Generate an image through OpenRouter's images endpoint (stdlib only).

  generate.py --prompt "a red fox, flat vector" --out fox.png
  generate.py --prompt-file p.txt --ref style.png --ref pose.webp --size 1536x1024 --quality high --out out.png

Key lookup: $OPENROUTER_API_KEY, else the 1Password reference in $IMAGE_GEN_KEY_REF
(read via ~/hq/bin/keychain-secret when present, then `op read`). Never printed or logged.
Every real call is appended to $IMAGE_GEN_LOG (default ~/.cache/image-gen/gen-log.jsonl).
Refuses to start when today's logged spend reaches $IMAGE_GEN_DAILY_CAP (default 5.00 USD).
"""
import argparse, base64, json, mimetypes, os, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path

URL = "https://openrouter.ai/api/v1/images"
DEFAULT_KEY_REF = "op://Private/OpenRouter - API keys/music-video-images - key"
LOG = Path(os.environ.get("IMAGE_GEN_LOG", "~/.cache/image-gen/gen-log.jsonl")).expanduser()
CAP = float(os.environ.get("IMAGE_GEN_DAILY_CAP", "5.00"))


def read_key():
    if os.environ.get("OPENROUTER_API_KEY"):
        return os.environ["OPENROUTER_API_KEY"]
    ref = os.environ.get("IMAGE_GEN_KEY_REF", DEFAULT_KEY_REF)
    helper = Path.home() / "hq/bin/keychain-secret"
    for cmd in ([str(helper), ref] if helper.exists() else []), ["op", "read", ref]:
        if cmd:
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip()
    sys.exit("no API key: set OPENROUTER_API_KEY or unlock 1Password for " + ref)


def cost_of(usage):  # BYOK reports cost 0 and the real price under cost_details
    return usage.get("cost") or usage.get("cost_details", {}).get("upstream_inference_cost") or 0


def spent_today():
    if not LOG.exists():
        return 0.0
    today = time.strftime("%F")
    return sum(cost_of(r.get("usage", {})) for r in map(json.loads, LOG.read_text().splitlines())
               if r.get("ts", "").startswith(today))


def data_url(path):
    mime = mimetypes.guess_type(path)[0] or "image/png"
    return f"data:{mime};base64," + base64.b64encode(Path(path).read_bytes()).decode()


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = a.add_mutually_exclusive_group(required=True)
    g.add_argument("--prompt")
    g.add_argument("--prompt-file")
    a.add_argument("--out", required=True, help="output PNG; with --n>1 gets _1, _2 suffixes")
    a.add_argument("--ref", action="append", default=[], help="reference image (repeatable, any format)")
    a.add_argument("--model", default="openai/gpt-image-2")
    a.add_argument("--size", help="WxH, multiples of 16, e.g. 1536x1024 (about $0.17 high), 2304x1536 (about $0.26)")
    a.add_argument("--aspect-ratio", help="e.g. 3:2, 16:9 (alternative to --size)")
    a.add_argument("--quality", choices=["low", "medium", "high", "auto"])
    a.add_argument("--n", type=int, default=1, help="number of separate calls")
    a.add_argument("--dry-run", action="store_true", help="build the request, call nothing")
    a = a.parse_args()

    prompt = a.prompt or Path(a.prompt_file).read_text().strip()
    body = {"model": a.model, "prompt": prompt}
    for k, v in (("size", a.size), ("aspect_ratio", a.aspect_ratio), ("quality", a.quality)):
        if v:
            body[k] = v
    if a.ref:
        body["input_references"] = [{"type": "image_url", "image_url": {"url": data_url(r)}} for r in a.ref]
    if a.dry_run:
        print(f"dry run ok, {len(json.dumps(body))} bytes, spent today ${spent_today():.2f} of ${CAP:.2f}")
        return
    if spent_today() >= CAP:
        sys.exit(f"daily cap reached (${spent_today():.2f} >= ${CAP:.2f}); raise IMAGE_GEN_DAILY_CAP to continue")

    key, out = read_key(), Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    LOG.parent.mkdir(parents=True, exist_ok=True)
    for i in range(a.n):
        req = urllib.request.Request(URL, json.dumps(body).encode(),
                                     {"Authorization": "Bearer " + key, "Content-Type": "application/json"})
        t0, rec = time.time(), {"ts": time.strftime("%F %T"), "model": a.model, "prompt": prompt[:200],
                                "refs": a.ref, "size": a.size, "quality": a.quality}
        try:
            resp = json.load(urllib.request.urlopen(req, timeout=600))
        except urllib.error.HTTPError as e:
            err = f"HTTP {e.code}: {e.read().decode()[:400]}"
            LOG.open("a").write(json.dumps({**rec, "error": err}) + "\n")
            sys.exit(err)
        raws = [base64.b64decode(d["b64_json"]) for d in resp.get("data", [])]
        paths = []
        for j, raw in enumerate(raws):
            suffix = "" if a.n == 1 and len(raws) == 1 else f"_{i+1}" + (f"_{j+1}" if len(raws) > 1 else "")
            p = out.with_name(out.stem + suffix + ".png")
            p.write_bytes(raw)
            paths.append(str(p))
            print(p)
        usage = resp.get("usage", {})
        LOG.open("a").write(json.dumps({**rec, "seconds": round(time.time() - t0, 1), "usage": usage,
                                        "outputs": paths}) + "\n")
        print(f"cost ${cost_of(usage):.3f} ({round(time.time() - t0, 1)}s)")
        if not raws:
            sys.exit("no image in response: " + json.dumps(resp, default=str)[:400])


if __name__ == "__main__":
    main()
