#!/usr/bin/env python3
"""watch-pending.py - one-shot watcher for the "Pending tasks" section of the
orchestration status doc.

Behaviour mirrors the child tracker (track-children.py): it blocks in a steady
poll until the Pending-tasks section settles with *newly added* items, then
prints those items as JSON and exits 0. Removal-only changes (e.g. the
task-creator moving items out to the Tasks section) are folded into the baseline
silently and polling continues, so a cycle only returns when there is real work
to dispatch.

An item is a top-level `- [ ]` line with a non-empty title, together with any
following indented sub-bullet lines (its "block"). Checked (`- [x]`) items and
empty-title checkboxes are ignored.

State lives in <state-dir>/baseline.json (a list of item titles).

Run it as an orchestrator-owned background process (never block inside a
subagent - the subagent's Bash call is capped ~600s and the blocked script gets
orphaned). Pass `--max-wait` so it exits cleanly for a relaunch instead of being
killed by a shell timeout.

Flags:
  --file PATH        status doc (required)
  --section NAME     section heading text (default "Pending tasks")
  --state-dir DIR    where baseline.json lives (default /tmp/pending-watch)
  --poll SECS        steady re-check interval (default 15)
  --debounce SECS    per-change settle interval (default 5)
  --max SECS         max debounce before settling by timeout (default 60)
  --max-wait SECS    if >0, exit 0 with added:[] after this many seconds of no
                     added-item settle (lets the caller re-run cleanly)
  --once             single check vs baseline, print added, update baseline, exit
  --seed             set baseline := current items, print summary, exit
  --reset            clear baseline before running
"""
import argparse, json, os, re, sys, time

TOP = re.compile(r'^- \[([ xX])\]\s*(.*)$')

def read_section(path, section):
    try:
        text = open(path, encoding='utf-8').read()
    except FileNotFoundError:
        return []
    lines = text.splitlines()
    out, in_sec = [], False
    for ln in lines:
        if ln.startswith('## '):
            in_sec = ln[3:].strip() == section
            continue
        if in_sec:
            out.append(ln)
    return out

def parse_items(section_lines):
    """Return list of {title, block} for unchecked, non-empty top-level items."""
    items, cur = [], None
    def flush():
        if cur and cur['checked'] is False and cur['title'].strip():
            block = '\n'.join(cur['lines']).rstrip()
            items.append({'title': cur['title'].strip(), 'block': block})
    for ln in section_lines:
        m = TOP.match(ln)
        if m:
            flush()
            cur = {'checked': m.group(1).lower() == 'x',
                   'title': m.group(2), 'lines': [ln]}
        elif cur is not None:
            # continuation only if indented or blank; a flush-and-stop otherwise
            if ln.strip() == '' or ln[:1] in (' ', '\t'):
                cur['lines'].append(ln)
            else:
                flush(); cur = None
    flush()
    return items

def current_items(path, section):
    return parse_items(read_section(path, section))

def load_baseline(state_dir):
    p = os.path.join(state_dir, 'baseline.json')
    try:
        return json.load(open(p))
    except (FileNotFoundError, json.JSONDecodeError):
        return []

def save_baseline(state_dir, titles):
    os.makedirs(state_dir, exist_ok=True)
    json.dump(titles, open(os.path.join(state_dir, 'baseline.json'), 'w'))

def added(items, baseline_titles):
    bset = set(baseline_titles)
    return [it for it in items if it['title'] not in bset]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--file', required=True)
    ap.add_argument('--section', default='Pending tasks')
    ap.add_argument('--state-dir', default='/tmp/pending-watch')
    ap.add_argument('--poll', type=float, default=15)
    ap.add_argument('--debounce', type=float, default=5)
    ap.add_argument('--max', type=float, default=60)
    ap.add_argument('--max-wait', type=float, default=0,
                    help='if >0, exit 0 with added:[] after this many seconds '
                         'of no added-item settle (lets the caller re-run '
                         'cleanly instead of being killed by a shell timeout)')
    ap.add_argument('--once', action='store_true')
    ap.add_argument('--seed', action='store_true')
    ap.add_argument('--reset', action='store_true')
    a = ap.parse_args()

    if a.reset:
        save_baseline(a.state_dir, [])

    if a.seed:
        items = current_items(a.file, a.section)
        save_baseline(a.state_dir, [it['title'] for it in items])
        print(json.dumps({'seeded': [it['title'] for it in items]}))
        return

    if a.once:
        items = current_items(a.file, a.section)
        add = added(items, load_baseline(a.state_dir))
        save_baseline(a.state_dir, [it['title'] for it in items])
        print(json.dumps({'added': add, 'all_current': [it['title'] for it in items]}))
        return

    # steady poll until a settled change with newly-added items
    started = time.time()
    while True:
        baseline = load_baseline(a.state_dir)
        items = current_items(a.file, a.section)
        titles = [it['title'] for it in items]
        if titles == baseline or (set(titles) == set(baseline)):
            if a.max_wait > 0 and time.time() - started >= a.max_wait:
                # bounded idle exit so a caller can re-run cleanly (not killed)
                print(json.dumps({'added': [], 'all_current': titles,
                                  'timed_out': True}))
                return
            time.sleep(a.poll)
            continue

        # something differs -> debounce until stable
        stable_since = time.time()
        last = titles
        deadline = time.time() + a.max
        while True:
            time.sleep(a.debounce)
            items = current_items(a.file, a.section)
            titles = [it['title'] for it in items]
            if titles != last:
                last = titles
                stable_since = time.time()
                if time.time() >= deadline:
                    break
                continue
            if time.time() - stable_since >= a.debounce or time.time() >= deadline:
                break

        add = added(items, baseline)
        # fold current state into baseline regardless (covers removals)
        save_baseline(a.state_dir, titles)
        if add:
            print(json.dumps({'added': add, 'all_current': titles}))
            return
        # removal-only change: keep watching
        continue

if __name__ == '__main__':
    main()
