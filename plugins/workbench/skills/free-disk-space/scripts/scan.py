#!/usr/bin/env python3
"""Scan a directory (default $HOME) with du and write a classified tree as JSON.
usage: scan.py [root] [-o tree.json] [--depth 4] [--min-mb 50]"""
import argparse, fnmatch, json, os, subprocess, sys

ap = argparse.ArgumentParser()
ap.add_argument("root", nargs="?", default=os.path.expanduser("~"))
ap.add_argument("-o", "--out", default="/tmp/free-disk-space-tree.json")
ap.add_argument("--depth", type=int, default=4)
ap.add_argument("--min-mb", type=float, default=50)
a = ap.parse_args()
root = os.path.realpath(a.root)
cat = json.load(open(os.path.join(os.path.dirname(__file__), "..", "targets.json")))
home = os.path.expanduser("~")

# -x: stay on one filesystem; -k: KiB. Permission errors are expected, drop them.
p = subprocess.run(["du", "-akxd", str(a.depth), root], capture_output=True, text=True)
tree = {"name": root, "path": root, "size": 0, "children": {}}
for line in p.stdout.splitlines():
    kb, _, path = line.partition("\t")
    if path == root:
        tree["size"] = int(kb) * 1024
        continue
    node = tree
    for part in os.path.relpath(path, root).split(os.sep):
        node = node["children"].setdefault(part, {"name": part, "path": None, "size": 0, "children": {}})
    node["path"], node["size"] = path, int(kb) * 1024

def classify(path, name, inherited):
    rel = os.path.relpath(path, home)
    if any(rel == q or rel.startswith(q + os.sep) for q in cat["protected"]):
        return {"tier": "protected", "note": "Never delete"}
    hit = None
    for t in cat["targets"]:   # later, more specific entries override earlier ones
        if ("path" in t and fnmatch.fnmatch(rel, t["path"])) or t.get("name") == name:
            hit = t
    if hit:
        return {k: hit[k] for k in ("tier", "note", "cmd") if k in hit}
    return inherited

min_b = a.min_mb * 1024 * 1024
def finish(node, inherited):
    info = classify(node["path"], node["name"], inherited) if node["path"] else inherited
    kids = [finish(c, info if info and info.get("tier") != "decide" else None)
            for c in node["children"].values() if c["size"] >= min_b]
    out = {"name": node["name"], "path": node["path"], "size": node["size"], "tier": (info or {}).get("tier", "unknown")}
    for k in ("note", "cmd"):
        if info and k in info: out[k] = info[k]
    if kids: out["children"] = sorted(kids, key=lambda c: -c["size"])
    return out

json.dump(finish(tree, None), open(a.out, "w"))
print(a.out, f"{tree['size']/2**30:.1f} GiB scanned", file=sys.stderr)
