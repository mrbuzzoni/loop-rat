#!/usr/bin/env python3
"""List receipts, filtered the way you actually look for them.

  list_receipts.py <receipts-dir> [--limit N] [--loop NAME] [--verdict V]
                   [--since 3d|12h|30m] [--json]

Defaults to the newest ten in a fixed-width table. `--json` prints an array
instead, so a status bar or a monitoring check can read it without parsing
columns.
"""
import json
import os
import re
import signal
import sys
import time

signal.signal(signal.SIGPIPE, signal.SIG_DFL)


def parse_since(text):
    match = re.fullmatch(r"(\d+)([mhd])", str(text).strip().lower())
    if not match:
        return None
    amount, unit = int(match.group(1)), match.group(2)
    return amount * {"m": 60, "h": 3600, "d": 86400}[unit]


def load(root):
    rows = []
    for base, _dirs, files in os.walk(root):
        if "receipt.json" not in files:
            continue
        path = os.path.join(base, "receipt.json")
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            continue
        data["_dir"] = base
        data["_day"] = os.path.basename(os.path.dirname(base))
        data["_mtime"] = os.path.getmtime(path)
        rows.append(data)
    rows.sort(key=lambda r: r["_mtime"], reverse=True)
    return rows


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    root = argv[1]
    args = argv[2:]

    def opt(name, default=None):
        if name in args:
            i = args.index(name)
            return args[i + 1] if len(args) > i + 1 else default
        return default

    limit = int(opt("--limit", "10"))
    loop = opt("--loop")
    verdict = opt("--verdict")
    since = parse_since(opt("--since", "")) if opt("--since") else None
    as_json = "--json" in args

    if not os.path.isdir(root):
        if as_json:
            print("[]")
        else:
            print("no receipts yet - try: bin/shift digest --dry-run")
        return 0

    rows = load(root)
    now = time.time()
    if loop:
        rows = [r for r in rows if r.get("loop") == loop]
    if verdict:
        rows = [r for r in rows if r.get("verdict") == verdict]
    if since:
        rows = [r for r in rows if now - r["_mtime"] <= since]
    rows = rows[:limit]

    if as_json:
        for row in rows:
            row["path"] = os.path.relpath(row.pop("_dir"))
            row.pop("_mtime", None)
            row.pop("_day", None)
        print(json.dumps(rows, indent=2))
        return 0

    if not rows:
        print("nothing matches that filter")
        return 0

    for row in rows:
        print("%-11s %-14s %-13s %5ss  $%-8.4f %s" % (
            row["_day"], row.get("loop", ""), row.get("verdict", ""),
            row.get("duration_seconds", 0), float(row.get("cost_usd", 0) or 0),
            os.path.basename(row["_dir"])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
