#!/usr/bin/env python3
"""Turn one or more grader answers into a single verdict.

  merge_grades.py <out.json> <raw-1> [<raw-2> ...]

One grader: its verdict, as read. Two or more: the most cautious verdict wins,
and any disagreement is itself a finding - it means the work sits on a line the
rubric does not draw clearly, which is exactly the thing worth a human minute in
the morning.

Prints the final verdict on stdout.
"""
import json
import os
import re
import sys

SEVERITY = {"pass": 1, "needs-review": 2, "fail": 3, "blocked": 4}


def read_one(path):
    """What this grader said, and why we could or could not read it."""
    try:
        with open(path, "r", encoding="utf-8") as fh:
            raw = fh.read()
    except OSError:
        return None, "the grading call left no answer"

    if "[dry run]" in raw:
        return None, "dry run - no grader was called"
    if "spend cap" in raw:
        return None, ("no grader ran: the shift was out of budget before it could "
                      "be graded, so this work is unreviewed rather than approved")
    if not raw.strip():
        return None, "no grader ran: the grading call produced nothing"

    match = re.search(r"\{.*\}", raw, re.S)
    if not match:
        return None, "the grader answered, but not with JSON this harness could read"
    try:
        parsed = json.loads(match.group(0))
    except ValueError:
        return None, "the grader's JSON did not parse"
    if not isinstance(parsed, dict) or not parsed.get("verdict"):
        return None, "the grader's answer had no verdict in it"
    return parsed, None


def main(argv):
    out_path, raws = argv[1], argv[2:]
    reads, notes = [], []
    for path in raws:
        parsed, why = read_one(path)
        if parsed:
            reads.append(parsed)
        elif why:
            notes.append(why)

    if not reads:
        grade = {"verdict": "needs-review", "score": None,
                 "graders": 0, "agreement": None,
                 "notes": notes[0] if notes else "no grader answered"}
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump(grade, fh, indent=2)
            fh.write("\n")
        print(grade["verdict"])
        return 0

    verdicts = [str(r.get("verdict", "needs-review")) for r in reads]
    agreement = len(set(verdicts)) == 1
    worst = max(verdicts, key=lambda v: SEVERITY.get(v, 2))
    if not agreement and SEVERITY.get(worst, 2) < SEVERITY["needs-review"]:
        worst = "needs-review"

    scores = [r.get("score") for r in reads if isinstance(r.get("score"), (int, float))]
    grade = {
        "verdict": worst,
        "score": round(sum(scores) / float(len(scores))) if scores else None,
        "graders": len(reads),
        "agreement": agreement,
        "notes": reads[0].get("notes", ""),
        "fix_first": reads[0].get("fix_first", ""),
    }

    if not agreement:
        grade["verdicts"] = verdicts
        grade["notes"] = (
            "the graders disagreed (%s). Two readings of the same work parted "
            "company, which is a question for you rather than a fault in the "
            "work: %s"
            % (", ".join(verdicts),
               " | ".join(filter(None, (r.get("notes", "") for r in reads))))
        )
    if len(reads) > 1:
        grade["each"] = [
            {"verdict": r.get("verdict"), "score": r.get("score"),
             "notes": r.get("notes", "")}
            for r in reads
        ]

    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(grade, fh, indent=2)
        fh.write("\n")
    print(grade["verdict"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
