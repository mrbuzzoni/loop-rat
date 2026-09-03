#!/usr/bin/env python3
"""Say how a replay differs from the shift it came from.

Two answers to the same brief are rarely identical, and that is not the
question. The question is whether they agree about what to do. So: how much text
moved, whether both changed the same number of files, and the first line where
they part company.
"""
import difflib
import json
import os
import sys


def read(path, name):
    try:
        with open(os.path.join(path, name), "r", encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return ""


def receipt(path):
    try:
        with open(os.path.join(path, "receipt.json"), "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def main(argv):
    original, replay = argv[1], argv[2]
    a, b = read(original, "output.md"), read(replay, "output.md")
    ra, rb = receipt(original), receipt(replay)

    print("## replay of %s" % os.path.basename(original.rstrip("/")))
    print()
    print("| | original | replay |")
    print("|---|---|---|")
    print("| verdict | %s | %s |" % (ra.get("verdict", "?"), rb.get("verdict", "?")))
    print("| files changed | %s | %s |" % (
        ra.get("guard", {}).get("files_changed", "?"),
        rb.get("guard", {}).get("files_changed", "?")))
    print("| cost | $%.4f | $%.4f |" % (
        float(ra.get("cost_usd", 0) or 0), float(rb.get("cost_usd", 0) or 0)))
    print("| report length | %d chars | %d chars |" % (len(a), len(b)))
    print()

    if not a or not b:
        print("One of the two reports is empty, so there is nothing to compare.")
        return 0

    ratio = difflib.SequenceMatcher(None, a, b).ratio()
    print("Text similarity: %.0f%%" % (ratio * 100))
    if ratio > 0.98:
        print("The two answers are effectively the same. Whatever you saw came "
              "from the plan, not from the model's mood.")
    elif ratio > 0.6:
        print("Same shape, different wording. Read the first divergence below "
              "and decide whether it changes the conclusion.")
    else:
        print("The two answers disagree. A brief that produces this much variance "
              "is under-specified: tighten the plan's output shape or its stop "
              "conditions.")
    print()

    a_lines, b_lines = a.splitlines(), b.splitlines()
    for line in difflib.unified_diff(a_lines, b_lines, "original", "replay",
                                     n=1, lineterm=""):
        print(line)
        if line.startswith("+") and not line.startswith("+++"):
            break
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
