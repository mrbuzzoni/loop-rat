#!/usr/bin/env python3
"""Turn one raw agent response into: the answer, the cost, and an exit code.

  agent_result.py <raw.json> <cost-file> <result-field> <cost-field>

Prints the model's answer on stdout and writes the dollar amount to the cost
file. Exits 1 if the response says it failed, so the shift records an error
instead of an empty success.
"""
import json
import os
import sys


def main(argv):
    raw_path, cost_path, result_field, cost_field = argv[1:5]
    with open(cost_path, "w", encoding="utf-8") as fh:
        fh.write("0.0000\n")                    # until proven otherwise

    if not os.path.exists(raw_path) or os.path.getsize(raw_path) == 0:
        sys.stdout.write("**The shift could not reach the model.**\n\n"
                         "The agent produced no response at all.\n")
        sys.stderr.write("agent produced no response\n")
        return 1

    try:
        with open(raw_path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except ValueError:
        # Not JSON: an agent that answers in plain text is allowed to.
        with open(raw_path, "r", encoding="utf-8", errors="replace") as fh:
            sys.stdout.write(fh.read())
        return 0

    if isinstance(data, list):                  # stream-json transcripts
        data = next(
            (m for m in reversed(data) if isinstance(m, dict) and result_field in m),
            {},
        )

    cost = 0.0
    try:
        cost = float(data.get(cost_field, 0) or 0)
    except (TypeError, ValueError):
        pass
    with open(cost_path, "w", encoding="utf-8") as fh:
        fh.write("%.4f\n" % cost)

    answer = data.get(result_field, "")
    if data.get("is_error") or data.get("subtype") in ("error_max_turns", "error_during_execution"):
        message = answer or data.get("subtype") or "no reason given"
        # Written to stdout as well as stderr: output.md is the file a human
        # actually opens in the morning, and a silent empty file explains nothing.
        sys.stdout.write("**The shift could not reach the model.**\n\n%s\n" % message)
        sys.stderr.write("agent reported failure: %s\n" % message)
        return 1

    sys.stdout.write(str(answer))
    if not str(answer).endswith("\n"):
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
