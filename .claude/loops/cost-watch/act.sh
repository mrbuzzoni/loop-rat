#!/usr/bin/env bash
# act.sh - count first, ask second.
#
# Every number in the report comes from report.py. The model is asked for the
# reading, never for the arithmetic - a model that adds up its own costs is the
# one thing a cost watcher must not be.
set -uo pipefail

FACTS="$RAT_RECEIPT/numbers.md"
COST_WATCH_DAYS="${COST_WATCH_DAYS:-14}" \
  python3 "$RAT_ROOT/.claude/loops/cost-watch/report.py" > "$FACTS" 2>"$RAT_RECEIPT/report.err"

SHIFTS="$(grep -c '^| [a-z]' "$FACTS" 2>/dev/null || echo 0)"
if [ "${SHIFTS:-0}" -lt 1 ]; then
  echo "**What I found** - not enough history to read yet."
  echo
  cat "$FACTS"
  echo
  echo "**What I changed** - nothing, and no model was called."
  exit 0
fi

{
  cat "$RAT_RECEIPT/prompt.md"
  echo
  echo "## The numbers"
  echo
  cat "$FACTS"
} | rat-agent --tag act
STATUS=$?

printf '{"loops_seen":%s}\n' "${SHIFTS:-0}" > "$RAT_RECEIPT/cursor.json"
exit "$STATUS"
