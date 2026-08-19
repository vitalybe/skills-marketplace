#!/usr/bin/env bash
# Pull the canonical aie-devflow bundle (in the DriveNets ai-enablement-skills
# repo) into this marketplace as the devflow plugin. The department repo is the
# SOURCE OF TRUTH; this script publishes back, applying the mechanical transform:
#
#   - copy skills/, bin/, docs/ (rsync --delete, exec bits preserved)
#   - rewrite functional /aie-devflow: -> /devflow: slash commands
#   - regenerate .claude-plugin/plugin.json (name=devflow, author=Vitaly Belman;
#     description inherited from the source, version = source version if it is
#     ahead, otherwise a patch bump so the plugin cache actually invalidates)
#
# README.md and the marketplace catalog are hand-maintained here and left
# untouched. Idempotent - safe to re-run.
#
# Wired to a post-commit hook in the source repo; the git-sweep cron commits and
# pushes whatever lands here.
#
# Usage:
#   scripts/sync-from-aie.sh                 # apply, print what changed
#   AIE_SRC=/path/to/aie-devflow scripts/sync-from-aie.sh   # override source path
set -euo pipefail

SRC="${AIE_SRC:-$HOME/git/ai-enablement-skills/plugins/aie-devflow}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DST="$ROOT/plugins/devflow"

[ -d "$SRC" ] || { echo "source not found: $SRC (set AIE_SRC)" >&2; exit 1; }
[ -d "$DST" ] || { echo "destination plugin not found: $DST" >&2; exit 1; }

# 1. Functional content. --delete so deletions propagate; -a preserves +x bits.
for d in skills bin docs; do
  [ -d "$SRC/$d" ] && rsync -a --delete "$SRC/$d/" "$DST/$d/"
done

# 2. Rewrite functional slash-command references (${CLAUDE_PLUGIN_ROOT} paths are
#    name-independent and untouched).
# perl -pi, not sed -i: hooks and cron run under a bare PATH that resolves to BSD
# sed, whose -i needs a mandatory backup-suffix arg. perl -pi is identical on BSD
# and GNU, so it works regardless of PATH.
{ grep -rlZ "/aie-devflow:" "$DST/skills" "$DST/bin" "$DST/docs" 2>/dev/null || true; } \
  | xargs -0 -r perl -pi -e 's|/aie-devflow:|/devflow:|g'

# 3. Did the functional content change? (decides whether the version needs a bump)
cd "$ROOT"
CHANGED=$([ -n "$(git status --porcelain -- plugins/devflow)" ] && echo 1 || echo 0)

# 4. Regenerate the manifest: name + author forced, description inherited.
python3 - "$SRC/.claude-plugin/plugin.json" "$DST/.claude-plugin/plugin.json" "$CHANGED" <<'PY'
import json, sys
src, dst, changed = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
s, d = json.load(open(src)), json.load(open(dst))
out = {
    "name": "devflow",
    "description": s["description"],
    "version": d["version"],
    "author": {"name": "Vitaly Belman", "email": "vbelman@drivenets.com"},
}
if changed or out != d:
    parts = lambda v: tuple(int(x) for x in v.split("."))
    sv, dv = s.get("version", "0.1.0"), d["version"]
    # The source repo's release CI bumps its version only after the commit that
    # fires this sync, so an equal/older source version still needs a local bump -
    # Claude Code keys the plugin cache by version and would serve the stale copy.
    if parts(sv) > parts(dv):
        out["version"] = sv
    else:
        major, minor, patch = parts(dv)
        out["version"] = f"{major}.{minor}.{patch + 1}"
    with open(dst, "w") as f:
        json.dump(out, f, indent=2); f.write("\n")
    print(f"devflow manifest regenerated (version {out['version']})")
PY

# 5. Guard: no stray /aie-devflow: left behind.
if grep -rn "/aie-devflow:" "$DST" >/dev/null 2>&1; then
  echo "WARNING: residual /aie-devflow: references remain:" >&2
  grep -rn "/aie-devflow:" "$DST" >&2
fi

if [ -z "$(git status --porcelain -- plugins/devflow)" ]; then
  echo "no changes - devflow already in sync with aie-devflow."
  exit 0
fi

echo "sync: $SRC -> $DST"
git status --short -- plugins/devflow
