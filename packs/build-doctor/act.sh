#!/usr/bin/env bash
# act.sh - try the project from clean, ask only when something broke.
set -uo pipefail

FACTS="$RAT_RECEIPT/steps.md"
"$RAT_ROOT/.claude/loops/build-doctor/check.sh" > "$FACTS" 2>"$RAT_RECEIPT/check.err"

FAILED="$(sed -n 's/^failed-step: //p' "$FACTS" | tail -n 1)"
if [ "${FAILED:-none}" = "none" ]; then
  echo "**What I found** - the project still installs and builds from a clean checkout."
  echo
  grep '^- ' "$FACTS" || true
  echo
  echo "**What I changed** - nothing, and no model was called."
  exit 0
fi

{
  cat "$RAT_RECEIPT/prompt.md"
  echo
  echo "## What happened in the clean checkout"
  echo
  cat "$FACTS"
} | rat-agent --tag act
