#!/usr/bin/env python3
"""track-children.py - watch an orchestrator pane's child agents and block until
a *settled* change, then print it and exit. Designed to be run once per cycle by
the monitoring subagent, which processes the output and re-runs it; state
persists in the state dir so each run continues tracking where the last left off.

It does NOT loop forever inside the orchestrator. One invocation:

  1. Enumerate the children of --parent via `herdr agent children` and compare
     their agent_status (and set membership) against the persisted baseline.
  2. Steady phase: while nothing differs from the baseline, re-check every
     --poll seconds (default 20).
  3. Debounce phase: as soon as any child differs, track every differing child
     in parallel, re-checking every --debounce seconds (default 5). A child is
     settled once its status has held for one debounce interval; a child whose
     episode exceeds --max-debounce (default 60) settles by timeout. A child
     that reverts to its baseline status is treated as a blip and dropped.
  4. When every differing child has settled, write the change report to the
     state dir, print it to stdout, fold the new statuses into the baseline, and
     exit 0. If every difference turned out to be a blip, resume the steady phase.

"Change" = a child's agent_status changing OR a child appearing/disappearing
(new task spawned / tab closed). The debounce is what filters herdr's sub-second
idle blips, so no separate stable-idle wait is needed here.

State dir (default /tmp/herdr-monitoring):
  baseline.json  - {pane_id: {"status", "name"}} last settled snapshot; the
                   persisted memory that lets a restart continue tracking.
  latest.json    - the change report from the most recent settled exit.
  log.jsonl      - one JSON line appended per settled exit (history/debug).

Usage:
  track-children.py [--parent PANE] [--recursive]
                    [--poll SEC] [--debounce SEC] [--max-debounce SEC]
                    [--state-dir DIR] [--reset]

--parent defaults to $HERDR_PANE_ID. When this script runs inside a monitoring
subagent of the orchestrator, that env is inherited from the orchestrator, so it
resolves to the orchestrator's pane; pass --parent explicitly to be certain.

Requires: herdr (HERDR_ENV=1), python3.
"""
import argparse
import json
import os
import subprocess
import sys
import time


def die(msg, code=2):
    print(f"track-children: {msg}", file=sys.stderr)
    sys.exit(code)


def snapshot(parent, recursive):
    """Current children of `parent` as {pane_id: {"status", "name"}}.

    Returns None on a herdr/parse failure so the caller can retry rather than
    mistake a transient error for "every child disappeared".
    """
    cmd = ["herdr", "agent", "children", parent, "--json"]
    if recursive:
        cmd.append("--recursive")
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except Exception as e:  # noqa: BLE001 - any spawn failure is retriable
        print(f"track-children: herdr call failed: {e}", file=sys.stderr)
        return None
    if out.returncode != 0:
        print(f"track-children: herdr exited {out.returncode}: {out.stderr.strip()}", file=sys.stderr)
        return None
    try:
        agents = json.loads(out.stdout)["result"]["agents"]
    except Exception as e:  # noqa: BLE001
        print(f"track-children: bad herdr output: {e}", file=sys.stderr)
        return None
    return {
        a["pane_id"]: {"status": a.get("agent_status", "unknown"), "name": a.get("name", a["pane_id"])}
        for a in agents
        if "pane_id" in a
    }


def snapshot_retry(parent, recursive, tries=3, wait=2):
    for i in range(tries):
        snap = snapshot(parent, recursive)
        if snap is not None:
            return snap
        if i < tries - 1:
            time.sleep(wait)
    die("could not read children after retries")


def load_baseline(path):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return None
    except Exception as e:  # noqa: BLE001 - corrupt state: start fresh
        print(f"track-children: ignoring unreadable baseline ({e})", file=sys.stderr)
        return None


def save_json(path, data):
    tmp = f"{path}.tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)


def status_of(snap, pane):
    return snap[pane]["status"] if pane in snap else None


def diff_panes(baseline, cur):
    """Panes whose status differs between baseline and cur (incl. appear/disappear)."""
    changed = []
    for pane in set(baseline) | set(cur):
        if status_of(baseline, pane) != status_of(cur, pane):
            changed.append(pane)
    return changed


def is_settled(ep, now, debounce, max_debounce):
    stable = now - ep["stable_since"] >= debounce
    timed_out = now - ep["episode_start"] >= max_debounce
    return stable or timed_out


def update_episodes(episodes, baseline, cur, now):
    """Fold the latest snapshot into the per-pane debounce episodes.

    A pane differing from baseline starts/continues an episode; a fresh status
    resets its stability timer. A pane that matches baseline again reverted (a
    blip) and its episode is dropped.
    """
    for pane in set(baseline) | set(cur):
        bstat = status_of(baseline, pane)
        cstat = status_of(cur, pane)
        if bstat != cstat:
            ep = episodes.get(pane)
            if ep is None:
                episodes[pane] = {"episode_start": now, "last_status": cstat, "stable_since": now}
            elif ep["last_status"] != cstat:
                ep["last_status"] = cstat
                ep["stable_since"] = now
        else:
            episodes.pop(pane, None)


def build_report(episodes, baseline, cur, now, max_debounce):
    changes = []
    for pane, ep in episodes.items():
        frm = status_of(baseline, pane)
        to = status_of(cur, pane)
        if frm is None:
            kind = "appeared"
        elif to is None:
            kind = "disappeared"
        else:
            kind = "status"
        name = (cur.get(pane) or baseline.get(pane) or {}).get("name", pane)
        changes.append({
            "pane": pane,
            "name": name,
            "from": frm,
            "to": to,
            "kind": kind,
            "timed_out": now - ep["episode_start"] >= max_debounce,
        })
    changes.sort(key=lambda c: c["pane"])
    return changes


def debounce(parent, recursive, baseline, cur, debounce_sec, max_debounce, poll_ref):
    """Track every differing child in parallel until all settle. Returns
    (report, final_snapshot), or (None, None) if every difference was a blip."""
    episodes = {}
    now = time.time()
    update_episodes(episodes, baseline, cur, now)
    while True:
        if not episodes:
            return None, None  # all reverted; back to steady polling
        now = time.time()
        if all(is_settled(ep, now, debounce_sec, max_debounce) for ep in episodes.values()):
            return build_report(episodes, baseline, cur, now, max_debounce), cur
        time.sleep(debounce_sec)
        cur = snapshot_retry(parent, recursive)
        now = time.time()
        update_episodes(episodes, baseline, cur, now)


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--parent", default=os.environ.get("HERDR_PANE_ID", ""))
    ap.add_argument("--recursive", action="store_true")
    ap.add_argument("--poll", type=float, default=20.0)
    ap.add_argument("--debounce", type=float, default=5.0)
    ap.add_argument("--max-debounce", type=float, default=60.0)
    ap.add_argument("--state-dir", default="/tmp/herdr-monitoring")
    ap.add_argument("--reset", action="store_true")
    args = ap.parse_args()

    if os.environ.get("HERDR_ENV") != "1":
        die("not inside herdr (HERDR_ENV != 1)")
    if not args.parent:
        die("no parent pane - set $HERDR_PANE_ID or pass --parent <pane>")

    os.makedirs(args.state_dir, exist_ok=True)
    baseline_path = os.path.join(args.state_dir, "baseline.json")
    latest_path = os.path.join(args.state_dir, "latest.json")
    log_path = os.path.join(args.state_dir, "log.jsonl")

    if args.reset:
        for p in (baseline_path, latest_path):
            try:
                os.remove(p)
            except FileNotFoundError:
                pass

    baseline = load_baseline(baseline_path)
    cur = snapshot_retry(args.parent, args.recursive)

    # First run ever: adopt the current children as the baseline silently, so
    # pre-existing tasks aren't reported as spurious changes.
    if baseline is None:
        save_json(baseline_path, cur)
        baseline = cur

    # Steady phase. On a restart, the first comparison happens immediately so
    # changes that landed during the previous run's exit/restart gap aren't lost.
    while True:
        if diff_panes(baseline, cur):
            report, final = debounce(
                args.parent, args.recursive, baseline, cur, args.debounce, args.max_debounce, args.poll
            )
            if report:
                save_json(baseline_path, final)
                save_json(latest_path, report)
                with open(log_path, "a") as f:
                    f.write(json.dumps({"ts": time.time(), "changes": report}) + "\n")
                print(json.dumps(report, indent=2))
                return 0
            # every diff was a blip; re-read baseline stays, resume steady loop
        time.sleep(args.poll)
        cur = snapshot_retry(args.parent, args.recursive)


if __name__ == "__main__":
    sys.exit(main())
