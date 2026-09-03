#!/usr/bin/env bash
# act.sh - run it several times, and only ask about it if the runs disagreed.
set -uo pipefail

FACTS="$RAT_RECEIPT/runs.md"
"$RAT_ROOT/.claude/loops/flaky-finder/run.sh" > "$FACTS" 2>"$RAT_RECEIPT/run.err"

DISAGREE="$(sed -n 's/^disagreements: //p' "$FACTS" | tail -n 1)"
if [ "${DISAGREE:-0}" = "0" ]; then
  echo "**What I found** - every run agreed."
  echo
  head -n 3 "$FACTS"
  echo
  echo "**What I changed** - nothing, and no model was called."
  exit 0
fi

{
  cat "$RAT_RECEIPT/prompt.md"
  echo
  echo "## The runs"
  echo
  cat "$FACTS"
} | rat-agent --tag act
