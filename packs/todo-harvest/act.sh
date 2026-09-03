#!/usr/bin/env bash
# act.sh - collect the markers, then ask which five matter.
set -uo pipefail

FACTS="$RAT_RECEIPT/markers.md"
python3 "$RAT_ROOT/.claude/loops/todo-harvest/scan.py" > "$FACTS" 2>"$RAT_RECEIPT/scan.err"

COUNT="$(sed -n 's/^marker-count: //p' "$FACTS" | tail -n 1)"
if [ "${COUNT:-0}" = "0" ]; then
  echo "**What I found** - no TODO, FIXME, HACK or XXX markers in tracked files."
  echo
  echo "**What I changed** - nothing, and no model was called."
  exit 0
fi

{
  cat "$RAT_RECEIPT/prompt.md"
  echo
  echo "## The markers"
  echo
  cat "$FACTS"
} | rat-agent --tag act
