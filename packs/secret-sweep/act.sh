#!/usr/bin/env bash
# act.sh - search for credentials, ask only about what is ambiguous.
set -uo pipefail

FACTS="$RAT_RECEIPT/candidates.md"
python3 "$RAT_ROOT/.claude/loops/secret-sweep/sweep.py" > "$FACTS" 2>"$RAT_RECEIPT/sweep.err"

COUNT="$(sed -n 's/^candidate-count: //p' "$FACTS" | tail -n 1)"
if [ "${COUNT:-0}" = "0" ]; then
  echo "**What I found** - nothing shaped like a live credential in the tracked files."
  echo
  grep -c '^- ' "$FACTS" >/dev/null 2>&1 && \
    echo "Anything the scanner did match looked like a placeholder or a fixture."
  echo
  echo "**What I changed** - nothing, and no model was called."
  exit 0
fi

{
  cat "$RAT_RECEIPT/prompt.md"
  echo
  echo "## What the scanner found"
  echo
  cat "$FACTS"
} | rat-agent --tag act
