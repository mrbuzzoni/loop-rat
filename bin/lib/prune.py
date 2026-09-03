#!/usr/bin/env python3
"""Age out old receipts, keeping the ones you are more likely to want.

  prune.py <receipts-dir> <keep_days> <keep_failed_days> [--apply]

A shift that passed is evidence you probably never read. A shift that was
blocked, failed, or asked for review is the one you go back to weeks later when
the same thing happens again - so those are kept longer.

Without --apply it prints what it would remove and touches nothing. That is the
default on purpose: a command that deletes the record of unattended runs should
have to be asked twice.
"""
import json
import os
import shutil
import signal
import sys
import time

signal.signal(signal.SIGPIPE, signal.SIG_DFL)

KEPT_VERDICTS = ("pass",)


def verdict_of(receipt_dir):
    path = os.path.join(receipt_dir, "receipt.json")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh).get("verdict", "unknown")
    except (OSError, ValueError):
        return "unknown"          # an unreadable receipt is not a clean one


def main(argv):
    if len(argv) < 4:
        sys.stderr.write(__doc__)
        return 2

    root, keep_days, keep_failed_days = argv[1], int(argv[2]), int(argv[3])
    apply_it = "--apply" in argv[4:]
    now = time.time()

    if not os.path.isdir(root):
        print("no receipts yet - nothing to prune")
        return 0

    removed = kept = 0
    freed = 0
    for day in sorted(os.listdir(root)):
        day_dir = os.path.join(root, day)
        if not os.path.isdir(day_dir):
            continue
        for name in sorted(os.listdir(day_dir)):
            shift_dir = os.path.join(day_dir, name)
            if not os.path.isdir(shift_dir):
                continue
            age_days = (now - os.path.getmtime(shift_dir)) / 86400.0
            verdict = verdict_of(shift_dir)
            limit = keep_days if verdict in KEPT_VERDICTS else keep_failed_days
            if age_days <= limit:
                kept += 1
                continue
            size = sum(
                os.path.getsize(os.path.join(base, f))
                for base, _d, files in os.walk(shift_dir)
                for f in files
                if os.path.exists(os.path.join(base, f))
            )
            print("  %s  %-22s %-13s %4d days" % (day, name, verdict, age_days))
            if apply_it:
                shutil.rmtree(shift_dir, ignore_errors=True)
            removed += 1
            freed += size
        if apply_it and not os.listdir(day_dir):
            os.rmdir(day_dir)

    verb = "removed" if apply_it else "would remove"
    print("%s %d receipt(s), %.1f KB. %d kept." % (verb, removed, freed / 1024.0, kept))
    if removed and not apply_it:
        print("run it again with --apply to actually delete them")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
