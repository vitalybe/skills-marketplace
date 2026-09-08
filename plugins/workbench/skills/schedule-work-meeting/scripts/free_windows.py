#!/usr/bin/env python3
"""Turn find_meeting_availability probes into ranked, local-time free windows.

The availability API hands back one row per 30-minute slot, in UTC, with a
status per attendee - and stays silent about slots where someone is busy. Doing
the timezone shift, gap detection, stitching and working-hours clamp by hand
across a week of candidate days is slow and easy to get wrong, so do it here.

Two input formats. Prefer the compact one: the API responses already sit in
your context, and re-emitting them as JSON costs far more than transcribing
them as a letter grid.

  compact (cheap - one line per slot the API returned, times in UTC):

      #names orel vasily amir you
      2026-09-16 05:00 f f f f
      2026-09-16 05:30 f f f f
      2026-09-16 10:00 f t f f

      f=free  t=tentative  b=busy  o=oof  u=unknown, one letter per name in
      #names order (write "ffff" or "f f f f"). Include the organizer as a
      name. A slot you leave out is busy, exactly as in the API response.

  json (when you already have the response on disk): the raw tool output, a
      single object or a list of them.

    python3 free_windows.py --duration 90 scan.txt
    python3 free_windows.py --duration 90 --window 09:00-19:00 day-*.json
    python3 free_windows.py --selftest        # check the stitching logic
"""

import argparse
import glob
import json
import sys
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

# Worse status wins when merging, so a run is only "clean" if every slot is free.
TIERS = {"free": 0, "tentative": 1, "unknown": 2, "busy": 3, "oof": 3}
LETTERS = {"f": "free", "t": "tentative", "b": "busy", "o": "oof", "u": "unknown"}
SOFT = 2  # tentative/unknown are negotiable; busy and oof are not


def add(slots, start, end, people):
    """Record a slot, keeping the pessimistic reading if probes disagree."""
    tier = max((TIERS.get(s, 2) for s in people.values()), default=0)
    key = (start, end)
    if key not in slots or tier > slots[key][0]:
        slots[key] = (tier, people)


def parse_dt(node):
    """The API sends naive wall-clock plus a separate timeZone field."""
    raw = node["dateTime"].split(".")[0]
    zone = node.get("timeZone") or "UTC"
    try:
        tz = timezone.utc if zone.upper() == "UTC" else ZoneInfo(zone)
    except Exception:
        # Windows zone names ("Israel Standard Time") aren't IANA. UTC is the
        # documented fallback the API itself uses.
        tz = timezone.utc
    return datetime.fromisoformat(raw).replace(tzinfo=tz).astimezone(timezone.utc)


def collect_json(responses, slots):
    for resp in responses:
        for sug in resp.get("meetingTimeSuggestions", []):
            span = sug["meetingTimeSlot"]
            people = {}
            if sug.get("organizerAvailability"):
                people["you"] = sug["organizerAvailability"]
            for att in sug.get("attendeeAvailability", []):
                addr = att.get("attendee", {}).get("emailAddress", {}).get("address", "?")
                people[addr.split("@")[0]] = att.get("availability", "unknown")
            add(slots, parse_dt(span["start"]), parse_dt(span["end"]), people)
    return slots


def collect_compact(text, slots, slot_minutes):
    names = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("#names"):
            names = line.split()[1:]
            continue
        if line.startswith("#"):
            continue

        parts = line.split()
        if len(parts) < 3:
            raise SystemExit(f"need 'DATE TIME STATUSES', got: {raw!r}")
        day, hhmm, letters = parts[0], parts[1], parts[2:]
        if len(letters) == 1 and len(names) > 1:
            letters = list(letters[0])          # "fftf" as well as "f f t f"
        if names and len(letters) != len(names):
            raise SystemExit(
                f"{len(letters)} statuses for {len(names)} names: {raw!r}")

        start = datetime.fromisoformat(f"{day}T{hhmm}").replace(tzinfo=timezone.utc)
        people = {(names[i] if names else f"p{i}"): LETTERS.get(l.lower()[0], "unknown")
                  for i, l in enumerate(letters)}
        add(slots, start, start + timedelta(minutes=slot_minutes), people)
    return slots


def stitch(slots, threshold):
    """Merge consecutive slots at or under `threshold` into maximal runs."""
    runs = []
    for (start, end), (tier, people) in sorted(slots.items()):
        if tier > threshold:
            continue
        if runs and runs[-1]["end"] == start:
            runs[-1]["end"] = end
            runs[-1]["tier"] = max(runs[-1]["tier"], tier)
            for who, status in people.items():
                if TIERS.get(status, 2) > TIERS.get(runs[-1]["people"].get(who, "free"), 0):
                    runs[-1]["people"][who] = status
        else:
            runs.append({"start": start, "end": end, "tier": tier, "people": dict(people)})
    return runs


def clamp(run, tz, win_start, win_end, duration):
    """Cut a run down to the working window, one calendar day at a time."""
    out = []
    start, end = run["start"].astimezone(tz), run["end"].astimezone(tz)
    day = start.date()
    while day <= end.date():
        lo = max(start, datetime.combine(day, win_start, tzinfo=tz))
        hi = min(end, datetime.combine(day, win_end, tzinfo=tz))
        if hi - lo >= timedelta(minutes=duration):
            out.append({**run, "start": lo, "end": hi})
        day += timedelta(days=1)
    return out


def windows(slots, duration, tz, win_start, win_end):
    clean, soft = [], []
    for threshold, bucket in ((0, clean), (SOFT, soft)):
        for run in stitch(slots, threshold):
            bucket.extend(clamp(run, tz, win_start, win_end, duration))
    # A soft run that happens to be entirely free is just the clean run again.
    return clean, [r for r in soft if r["tier"] > 0]


def render(runs, label, empty):
    print(f"\n{label}")
    if not runs:
        print(f"  {empty}")
        return
    for r in sorted(runs, key=lambda r: r["start"]):
        mins = int((r["end"] - r["start"]).total_seconds() // 60)
        line = f"  {r['start']:%a %d %b}  {r['start']:%H:%M}-{r['end']:%H:%M}  ({mins} min)"
        held = sorted(w for w, s in r["people"].items() if TIERS.get(s, 2) > 0)
        print(f"{line}  holds: {', '.join(held)}" if held else line)


def selftest():
    """06:00-08:00Z free, 08:00-08:30Z omitted (= busy), 09:00-10:30Z tentative."""
    grid = """
    #names orel you
    2026-09-16 06:00 f f
    2026-09-16 06:30 ff
    2026-09-16 07:00 f f
    2026-09-16 07:30 f f
    2026-09-16 09:00 t f
    2026-09-16 09:30 t f
    2026-09-16 10:00 t f
    """
    tz = ZoneInfo("Asia/Jerusalem")  # UTC+3 in September
    nine, seven = datetime.min.time().replace(hour=9), datetime.min.time().replace(hour=19)

    slots = collect_compact(grid, {}, 30)
    clean, soft = windows(slots, 90, tz, nine, seven)
    assert len(clean) == 1, f"expected one clean run, got {clean}"
    # The omitted 08:00Z slot must break the run: 06:00-08:00Z, not 06:00-10:30Z.
    assert (clean[0]["end"] - clean[0]["start"]) == timedelta(hours=2), clean[0]
    assert (clean[0]["start"].hour, clean[0]["end"].hour) == (9, 11), clean[0]
    assert len(soft) == 1 and soft[0]["people"]["orel"] == "tentative", soft
    assert (soft[0]["end"] - soft[0]["start"]) == timedelta(minutes=90), soft[0]

    # A 09:00 floor must trim the 08:00-11:00 local block, not drop it.
    ten = datetime.min.time().replace(hour=10)
    trimmed, _ = windows(slots, 30, tz, ten, seven)
    assert trimmed[0]["start"].hour == 10, trimmed[0]

    # JSON input must agree with the compact grid it mirrors.
    as_json = {"meetingTimeSuggestions": [{
        "meetingTimeSlot": {
            "start": {"dateTime": "2026-09-16T06:00:00.0000000", "timeZone": "UTC"},
            "end": {"dateTime": "2026-09-16T06:30:00.0000000", "timeZone": "UTC"}},
        "organizerAvailability": "free",
        "attendeeAvailability": [
            {"attendee": {"emailAddress": {"address": "orel@x.com"}},
             "availability": "free"}]}]}
    assert collect_json([as_json], {}) == collect_compact(
        "#names you orel\n2026-09-16 06:00 f f", {}, 30)

    print("selftest ok")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="compact grids and/or raw JSON responses")
    ap.add_argument("--duration", type=int, default=30, help="meeting length in minutes")
    ap.add_argument("--tz", default="Asia/Jerusalem")
    ap.add_argument("--window", default="09:00-19:00", help="working hours, local")
    ap.add_argument("--slot", type=int, default=30, help="probe granularity in minutes")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    paths = [p for pattern in args.files for p in sorted(glob.glob(pattern))]
    texts = [open(p).read() for p in paths] if paths else [sys.stdin.read()]

    slots = {}
    for text in texts:
        if text.lstrip().startswith(("{", "[")):
            blob = json.loads(text)
            collect_json(blob if isinstance(blob, list) else [blob], slots)
        else:
            collect_compact(text, slots, args.slot)

    lo, hi = (datetime.strptime(t, "%H:%M").time() for t in args.window.split("-"))
    clean, soft = windows(slots, args.duration, ZoneInfo(args.tz), lo, hi)

    print(f"{args.duration}-min windows, {args.window} {args.tz}, {len(slots)} slots")
    render(clean, "EVERYONE FREE",
           "none - say which days you scanned, then offer the holds below")
    render(soft, "ONE OR MORE TENTATIVE", "none")


if __name__ == "__main__":
    main()
