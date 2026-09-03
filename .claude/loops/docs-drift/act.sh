#!/usr/bin/env bash
# act.sh - compare the CLI against its documentation.
#
# The comparison is done by scan.py, in python, with no model involved. The only
# question worth a token is which differences a reader would trip over.
set -uo pipefail

FACTS="$RAT_RECEIPT/drift.md"
python3 "$RAT_ROOT/.claude/loops/docs-drift/scan.py" > "$FACTS" 2>"$RAT_RECEIPT/scan.err"

# A loop with nothing to do should cost nothing. If every finding section is
# empty, the shift ends here and never opens a connection.
DRIFT="$(sed -n 's/^drift-count: //p' "$FACTS" | tail -n 1)"
if [ "${DRIFT:-0}" = "0" ]; then
  echo "**What I found** - the documentation matches the tool."
  echo
  echo "Every command in \`bin/rat\` is documented, every documented command exists,"
  echo "and every settings key is explained somewhere. Scanner output is in drift.md."
  echo
  echo "**What I changed** - nothing, and no model was called."
  printf '{"clean":true}\n' > "$RAT_RECEIPT/cursor.json"
  exit 0
fi

{
  cat "$RAT_RECEIPT/prompt.md"
  echo
  echo "## What the scanner found"
  echo
  cat "$FACTS"
} | rat-agent --tag act
STATUS=$?

printf '{"clean":false}\n' > "$RAT_RECEIPT/cursor.json"
exit "$STATUS"
