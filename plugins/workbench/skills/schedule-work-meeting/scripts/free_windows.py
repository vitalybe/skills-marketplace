#!/usr/bin/env python3
"""Turn find_meeting_availability probes into ranked, local-time free windows.

The availability API hands back one row per 30-minute slot, in UTC, with a
status per attendee - and stays silent about slots where someone is busy. Doing
the timezone shift, gap detection, stitching and working-hours clamp by hand
across a week of candidate days is slow and easy to get wrong, so do it here.

    python3 free_windows.py --duration 90 scan-*.json
    cat scan.json | python3 free_windows.py --duration 90

Input is the raw tool response(s): a single object, a list of them, or one file
per candidate day. Output is the windows at least `--duration` long, split into
ones where everybody is free and ones resting on a tentative hold.

    python3 free_windows.py --selftest    # check the stitching logic
"""

import argparse
import glob
import json
import sys
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

# Worse status wins when merging, so a run is only "clean" if every slot is free.
TIERS = {"free": 0, "tentative": 1, "unknown": 2, "busy": 3, "oof": 3}
SOFT = 2  # tentative/unknown are negotiable; busy and oof are not


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


def collect(responses):
    """Fold every probe into one deduped {(start, end): (tier, {who: status})}."""
    slots = {}
    for resp in responses:
        for sug in resp.get("meetingTimeSuggestions", []):
            span = sug["meetingTimeSlot"]
            key = (parse_dt(span["start"]), parse_dt(span["end"]))

            people = {}
            organizer = sug.get("organizerAvailability")
            if organizer:
                people["you"] = organizer
            for att in sug.get("attendeeAvailability", []):
                addr = att.get("attendee", {}).get("emailAddress", {}).get("address", "?")
                people[addr.split("@")[0]] = att.get("availability", "unknown")

            tier = max((TIERS.get(s, 2) for s in people.values()), default=0)
            # Overlapping probes can disagree; keep the pessimistic reading.
            if key not in slots or tier > slots[key][0]:
                slots[key] = (tier, people)
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


def windows(responses, duration, tz, win_start, win_end):
    slots = collect(responses)
    clean, soft = [], []
    for threshold, bucket in ((0, clean), (SOFT, soft)):
        for run in stitch(slots, threshold):
            bucket.extend(clamp(run, tz, win_start, win_end, duration))
    # A soft run that happens to be entirely free is just the clean run again.
    soft = [r for r in soft if r["tier"] > 0]
    return clean, soft


def render(runs, label, empty):
    print(f"\n{label}")
    if not runs:
        print(f"  {empty}")
        return
    for r in sorted(runs, key=lambda r: r["start"]):
        mins = int((r["end"] - r["start"]).total_seconds() // 60)
        line = (f"  {r['start']:%a %d %b}  {r['start']:%H:%M}-{r['end']:%H:%M}"
                f"  ({mins} min)")
        held = sorted(w for w, s in r["people"].items() if TIERS.get(s, 2) > 0)
        if held:
            print(f"{line}  holds: {', '.join(held)}")
        else:
            print(line)


def selftest():
    """06:00-08:00Z free, 08:00-08:30Z missing (= busy), 08:30-09:30Z free."""
    def slot(h, m, statuses):
        start = f"2026-09-16T{h:02d}:{m:02d}:00.0000000"
        end_h, end_m = (h, m + 30) if m == 0 else (h + 1, 0)
        return {
            "meetingTimeSlot": {
                "start": {"dateTime": start, "timeZone": "UTC"},
                "end": {"dateTime": f"2026-09-16T{end_h:02d}:{end_m:02d}:00.0000000",
                        "timeZone": "UTC"},
            },
            "organizerAvailability": "free",
            "attendeeAvailability": [
                {"attendee": {"emailAddress": {"address": f"{n}@x.com"}}, "availability": s}
                for n, s in statuses.items()
            ],
        }

    resp = {"meetingTimeSuggestions": [
        slot(6, 0, {"amir": "free"}), slot(6, 30, {"amir": "free"}),
        slot(7, 0, {"amir": "free"}), slot(7, 30, {"amir": "free"}),
        # 08:00 and 08:30 absent -> busy, so the run must break here.
        slot(9, 0, {"amir": "tentative"}), slot(9, 30, {"amir": "tentative"}),
        slot(10, 0, {"amir": "tentative"}),
    ]}

    tz = ZoneInfo("Asia/Jerusalem")  # UTC+3 in September
    clean, soft = windows([resp], 90, tz, datetime.min.time().replace(hour=9),
                          datetime.min.time().replace(hour=19))

    assert len(clean) == 1, f"expected one clean run, got {clean}"
    assert clean[0]["start"].hour == 9 and clean[0]["end"].hour == 11, clean[0]
    # The gap must not be bridged: 06:00-07:30Z is 90 min, 06:00-09:30Z is not.
    assert (clean[0]["end"] - clean[0]["start"]) == timedelta(hours=2)
    assert len(soft) == 1 and soft[0]["people"]["amir"] == "tentative", soft
    assert (soft[0]["end"] - soft[0]["start"]) == timedelta(minutes=90), soft[0]

    # A shorter meeting should also surface the tail of the clean block.
    clean30, _ = windows([resp], 30, tz, datetime.min.time().replace(hour=9),
                         datetime.min.time().replace(hour=19))
    assert len(clean30) == 1 and clean30[0]["end"].hour == 11

    print("selftest ok")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*", help="raw find_meeting_availability JSON")
    ap.add_argument("--duration", type=int, default=30, help="meeting length in minutes")
    ap.add_argument("--tz", default="Asia/Jerusalem")
    ap.add_argument("--window", default="09:00-19:00", help="working hours, local")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        selftest()
        return

    paths = [p for pattern in args.files for p in sorted(glob.glob(pattern))] \
        if args.files else []
    blobs = [json.load(open(p)) for p in paths] if paths else [json.load(sys.stdin)]

    responses = []
    for blob in blobs:
        responses.extend(blob if isinstance(blob, list) else [blob])

    tz = ZoneInfo(args.tz)
    lo, hi = (datetime.strptime(t, "%H:%M").time() for t in args.window.split("-"))
    clean, soft = windows(responses, args.duration, tz, lo, hi)

    print(f"{args.duration}-min windows, {args.window} {args.tz}, "
          f"{len(responses)} probe(s)")
    render(clean, "EVERYONE FREE", "none - report what you scanned, then offer the holds below")
    render(soft, "ONE OR MORE TENTATIVE", "none")


if __name__ == "__main__":
    main()
