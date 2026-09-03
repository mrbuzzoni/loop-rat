#!/usr/bin/env python3
"""Collect the notes-to-self, with how stale each one is.

Deterministic: git knows when each file last changed, and grep knows where the
markers are. The judgment about which ones matter is the only part worth a
model.
"""
import os
import re
import subprocess
import sys
import time

ROOT = os.environ.get("RAT_WORKDIR") or os.environ.get("RAT_ROOT", ".")
MARKERS = ("TODO", "FIXME", "HACK", "XXX")
SKIP = ("node_modules/", "vendor/", ".git/", "dist/", "build/", "state/")


def git(*args):
    proc = subprocess.run(["git", "-C", ROOT] + list(args),
                          capture_output=True, text=True, check=False)
    return proc.stdout if proc.returncode == 0 else ""


def last_touched(path):
    stamp = git("log", "-1", "--format=%ct", "--", path).strip()
    if not stamp:
        return None
    return (time.time() - float(stamp)) / 86400.0


def main():
    pattern = "|".join(MARKERS)
    out = git("grep", "-nE", r"\b(%s)\b" % pattern)
    if not out.strip():
        print("No markers found.")
        print()
        print("marker-count: 0")
        return 0

    rows = []
    ages = {}
    for line in out.splitlines():
        parts = line.split(":", 2)
        if len(parts) < 3:
            continue
        path, number, text = parts
        if any(skip in path for skip in SKIP):
            continue
        if path not in ages:
            ages[path] = last_touched(path)
        marker = re.search(r"\b(%s)\b" % pattern, text)
        rows.append((path, number, marker.group(1) if marker else "?",
                     ages[path], text.strip()[:120]))

    rows.sort(key=lambda r: (-(r[3] or 0), r[0]))

    print("### markers, oldest file first")
    print()
    for path, number, marker, age, text in rows[:60]:
        age_text = "%.0f days untouched" % age if age is not None else "not in git"
        print("- `%s:%s`  %s  (%s)" % (path, number, marker, age_text))
        print("      %s" % text)
    if len(rows) > 60:
        print("- ...and %d more" % (len(rows) - 60))
    print()

    stale = [r for r in rows if (r[3] or 0) > 90]
    print("### in files nobody has touched in three months: %d of %d"
          % (len(stale), len(rows)))
    print()
    print("marker-count: %d" % len(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
