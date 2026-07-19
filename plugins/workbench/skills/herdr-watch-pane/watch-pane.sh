#!/usr/bin/env bash
# Watch a herdr pane and exit as soon as its content SETTLES after a change.
# Prints the settled content (or a timeout notice) to stdout. Run this as a
# BACKGROUND task from an agent: the harness re-invokes the agent when the
# command exits, i.e. the moment the watched pane changes and settles.
#
# Usage:  watch-pane.sh <PANE_ID> [MAX_POLLS] [POLL_SECS] [DEBOUNCE_SECS]
#   PANE_ID        herdr pane id to watch (e.g. 1-2 or wR:pF). REQUIRED.
#   MAX_POLLS      max idle polls before giving up   (default 180 -> ~9 min at 3s)
#   POLL_SECS      seconds between polls while idle   (default 3)
#   DEBOUNCE_SECS  seconds between re-checks once a change is seen (default 1)
set -u

PANE="${1:?usage: watch-pane.sh <PANE_ID> [MAX_POLLS] [POLL_SECS] [DEBOUNCE_SECS]}"
MAX_POLLS="${2:-180}"
SLEEP="${3:-3}"
DEBOUNCE_SLEEP="${4:-1}"

# recent-unwrapped = scrollback with soft-wraps joined, so the hash is independent
# of pane width / resize / scroll position. Only genuine new output changes it.
read_pane() { herdr pane read "$PANE" --source recent-unwrapped --lines 60 2>/dev/null; }
hash_of()  { printf '%s' "$1" | shasum | awk '{print $1}'; }

prev_hash="$(hash_of "$(read_pane)")"

i=0
while [ "$i" -lt "$MAX_POLLS" ]; do
  sleep "$SLEEP"
  cur="$(read_pane)"
  [ -z "$cur" ] && { i=$((i + 1)); continue; }   # skip transient / failed reads
  cur_hash="$(hash_of "$cur")"
  if [ "$cur_hash" != "$prev_hash" ]; then
    # Change seen. Debounce: re-check every DEBOUNCE_SLEEP and only report once the
    # screen has stopped moving for one full interval (i.e. it has settled). This
    # avoids waking the agent on a half-drawn frame or mid-typed line.
    while :; do
      sleep "$DEBOUNCE_SLEEP"
      next="$(read_pane)"
      [ -z "$next" ] && continue
      next_hash="$(hash_of "$next")"
      [ "$next_hash" = "$cur_hash" ] && break     # stable -> settled
      cur="$next"; cur_hash="$next_hash"          # still moving -> keep waiting
    done
    echo "=== PANE $PANE CHANGED (settled) ==="
    printf '%s\n' "$cur"
    exit 0
  fi
  i=$((i + 1))
done

echo "=== PANE $PANE: no change after timeout ==="
printf '%s\n' "${cur:-}"
exit 0
