#!/usr/bin/env python3
"""A week of nights on one page, and whether the record can be trusted.

  audit.py <state-dir> [--days N] [--json]

Two halves. First the integrity check: every line of trace.log carries the hash
of the line before it, and every receipt line carries the hash the receipt had
when it was written. Recomputing both says whether anything was edited or
removed after the fact - including by an agent.

Then the summary: what ran, what it decided, what it cost, and what a person
still has to look at. Written for someone who was not there.
"""
import hashlib
import json
import os
import re
import signal
import sys
import time

signal.signal(signal.SIGPIPE, signal.SIG_DFL)


def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def check_chain(path):
    """Returns (checked, first_broken_line_number, anchored)."""
    if not os.path.exists(path):
        return 0, None, False
    with open(path, "r", encoding="utf-8") as fh:
        lines = [l.rstrip("\n") for l in fh if l.strip()]
    prev = ""
    anchored = False
    for number, line in enumerate(lines, 1):
        match = re.search(r" h=([0-9a-f]+)$", line)
        if not match:
            return number, number, anchored     # an unhashed line is a broken one
        body = line[: match.start()]
        expected = digest("%s|%s" % (prev, body))
        if expected != match.group(1):
            if number == 1:
                # After a rotation the first kept line refers to a line that is
                # no longer here. That is expected, and only for the first line.
                anchored = True
                prev = match.group(1)
                continue
            return len(lines), number, anchored
        prev = match.group(1)
    return len(lines), None, anchored


def check_receipts(state_dir, trace_path):
    """Receipts whose content no longer matches the hash the trace recorded."""
    edited, missing, checked = [], [], 0
    if not os.path.exists(trace_path):
        return checked, edited, missing
    with open(trace_path, "r", encoding="utf-8") as fh:
        for line in fh:
            if "phase=receipt" not in line:
                continue
            path = re.search(r"dir=(\S+)", line)
            recorded = re.search(r"rhash=([0-9a-f]+)", line)
            if not path or not recorded:
                continue
            checked += 1
            full = os.path.join(os.path.dirname(state_dir.rstrip("/")), path.group(1),
                                "receipt.json")
            if not os.path.exists(full):
                missing.append(path.group(1))
                continue
            with open(full, "r", encoding="utf-8") as rf:
                if digest(rf.read()) != recorded.group(1):
                    edited.append(path.group(1))
    return checked, edited, missing


def load_receipts(state_dir, days):
    root = os.path.join(state_dir, "receipts")
    cutoff = time.time() - days * 86400
    rows = []
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
        data["_path"] = os.path.relpath(base)
        rows.append(data)
    rows.sort(key=lambda r: r.get("started", ""))
    return rows


def main(argv):
    state_dir = argv[1] if len(argv) > 1 else "state"
    args = argv[2:]
    days = 7
    if "--days" in args:
        days = int(args[args.index("--days") + 1])
    as_json = "--json" in args

    trace = os.path.join(state_dir, "trace.log")
    checked, broken, anchored = check_chain(trace)
    r_checked, edited, missing = check_receipts(state_dir, trace)
    rows = load_receipts(state_dir, days)

    verdicts = {}
    for row in rows:
        verdicts[row.get("verdict", "?")] = verdicts.get(row.get("verdict", "?"), 0) + 1
    cost = sum(float(r.get("cost_usd", 0) or 0) for r in rows)
    needs_eyes = [r for r in rows
                  if r.get("verdict") in ("needs-review", "fail", "blocked", "interrupted")]

    if as_json:
        print(json.dumps({
            "trace_lines": checked,
            "chain_ok": broken is None,
            "first_broken_line": broken,
            "rotated": anchored,
            "receipts_checked": r_checked,
            "receipts_edited": edited,
            "receipts_missing": missing,
            "days": days,
            "shifts": len(rows),
            "verdicts": verdicts,
            "cost_usd": round(cost, 4),
        }, indent=2))
        return 0 if broken is None and not edited else 1

    print("## the record")
    if checked == 0:
        print("- no trace log yet, so there is nothing to attest")
    elif broken is None:
        print("- %d trace line(s), the chain holds%s"
              % (checked, " (rotated, so it starts mid-stream)" if anchored else ""))
    else:
        print("- the chain breaks at line %d of %d - everything after it was "
              "written or edited outside the harness" % (broken, checked))
    if r_checked:
        if edited:
            print("- %d receipt(s) no longer match what the trace recorded:" % len(edited))
            for path in edited:
                print("    %s" % path)
        elif missing:
            print("- %d receipt(s) recorded in the trace are gone (pruned, most likely)"
                  % len(missing))
        else:
            print("- %d receipt(s) match the hashes recorded when they were written"
                  % r_checked)
    print()

    print("## the last %d day(s)" % days)
    if not rows:
        print("- nothing ran")
        return 0 if broken is None else 1
    print("- %d shift(s), $%.4f spent" % (len(rows), cost))
    print("- verdicts: %s" % ", ".join("%s %d" % (k, v) for k, v in sorted(verdicts.items())))
    loops = sorted({r.get("loop", "?") for r in rows})
    print("- loops that ran: %s" % ", ".join(loops))
    interrupted = verdicts.get("interrupted", 0)
    if interrupted:
        print("- %d shift(s) were stopped before they finished" % interrupted)
    print()

    print("## still waiting on a person")
    if not needs_eyes:
        print("- nothing. every shift in this window ended clean.")
    for row in needs_eyes[-10:]:
        print("- %s  %s  %s" % (row.get("started", "")[:16], row.get("loop", "?"),
                                row.get("verdict", "?")))
        print("    %s" % row["_path"])
    return 0 if broken is None and not edited else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
