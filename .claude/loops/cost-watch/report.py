#!/usr/bin/env python3
"""What the loops have actually been doing, in numbers.

Reads receipts, the trace log and the spend ledger; prints a table per loop plus
the few facts a person would otherwise have to grep for. No model, no opinions -
the opinions are the shift's job.
"""
import json
import os
import re
import sys
import time

ROOT = os.environ.get("RAT_ROOT", ".")
WINDOW_DAYS = int(os.environ.get("COST_WATCH_DAYS", "14"))


def receipts():
    root = os.path.join(ROOT, "state", "receipts")
    cutoff = time.time() - WINDOW_DAYS * 86400
    out = []
    for base, _dirs, files in os.walk(root):
        if "receipt.json" not in files:
            continue
        path = os.path.join(base, "receipt.json")
        if os.path.getmtime(path) < cutoff:
            continue
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            continue
        data["_path"] = os.path.relpath(base, ROOT)
        data["_mtime"] = os.path.getmtime(path)
        out.append(data)
    out.sort(key=lambda r: r["_mtime"])
    return out


def skipped_starts():
    """Shifts that never began, and why. These never leave a receipt."""
    path = os.path.join(ROOT, "state", "trace.log")
    reasons = {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                if "status=skipped" not in line:
                    continue
                loop = re.search(r"loop=(\S+)", line)
                reason = re.search(r"reason=(\S+)", line)
                key = (loop.group(1) if loop else "?", reason.group(1) if reason else "?")
                reasons[key] = reasons.get(key, 0) + 1
    except OSError:
        pass
    return reasons


def mean(values):
    return sum(values) / float(len(values)) if values else 0.0


def main():
    rows = receipts()
    if not rows:
        print("No receipts in the last %d days. Nothing to read." % WINDOW_DAYS)
        return 0

    by_loop = {}
    for row in rows:
        by_loop.setdefault(row.get("loop", "?"), []).append(row)

    print("## %d shifts across %d loop(s), last %d days"
          % (len(rows), len(by_loop), WINDOW_DAYS))
    print()
    print("| loop | shifts | pass | review | fail | blocked | timeouts | avg s | avg $ | total $ |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for loop in sorted(by_loop):
        items = by_loop[loop]
        verdicts = [i.get("verdict", "?") for i in items]
        costs = [float(i.get("cost_usd", 0) or 0) for i in items]
        durations = [int(i.get("duration_seconds", 0) or 0) for i in items]
        timeouts = sum(1 for i in items if i.get("act", {}).get("status") == "timeout")
        print("| %s | %d | %d | %d | %d | %d | %d | %.0f | %.4f | %.4f |" % (
            loop, len(items),
            verdicts.count("pass"), verdicts.count("needs-review"),
            verdicts.count("fail"), verdicts.count("blocked"),
            timeouts, mean(durations), mean(costs), sum(costs)))
    print()

    print("### direction of travel")
    for loop in sorted(by_loop):
        items = by_loop[loop]
        if len(items) < 4:
            print("- %s: %d shifts, too few to call a trend" % (loop, len(items)))
            continue
        half = len(items) // 2
        older = mean([float(i.get("cost_usd", 0) or 0) for i in items[:half]])
        newer = mean([float(i.get("cost_usd", 0) or 0) for i in items[half:]])
        older_s = mean([int(i.get("duration_seconds", 0) or 0) for i in items[:half]])
        newer_s = mean([int(i.get("duration_seconds", 0) or 0) for i in items[half:]])
        drift = "flat"
        if older > 0 and newer > older * 1.35:
            drift = "cost rising"
        elif older > 0 and newer < older * 0.7:
            drift = "cost falling"
        print("- %s: $%.4f -> $%.4f, %.0fs -> %.0fs (%s)"
              % (loop, older, newer, older_s, newer_s, drift))
    print()

    skips = skipped_starts()
    print("### shifts that never started")
    if skips:
        for (loop, reason), count in sorted(skips.items(), key=lambda kv: -kv[1]):
            print("- %s: %d skipped, reason %s" % (loop, count, reason))
    else:
        print("- none")
    print()

    ledger = os.path.join(ROOT, "state", "budget.json")
    if os.path.exists(ledger):
        try:
            with open(ledger, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            days = data.get("days", {})
            recent = sorted(days.items())[-7:]
            print("### the ledger, last %d day(s)" % len(recent))
            for day, amount in recent:
                print("- %s  $%.4f" % (day, float(amount)))
        except (OSError, ValueError):
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
