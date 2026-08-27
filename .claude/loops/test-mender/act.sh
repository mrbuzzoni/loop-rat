#!/usr/bin/env bash
# act.sh - run the suite first, hand the model only what is red.
#
# The test command is deliberately discovered rather than configured: this loop
# should survive being copied into a repository that uses a different runner.
set -uo pipefail

RUN_LOG="$RAT_RECEIPT/tests-before.log"

detect_test_cmd() {
  if [ -f "$RAT_ROOT/Makefile" ] && grep -qE '^test:' "$RAT_ROOT/Makefile"; then
    echo "make test"
  elif [ -f "$RAT_ROOT/package.json" ] && grep -q '"test"' "$RAT_ROOT/package.json"; then
    echo "npm test --silent"
  elif { [ -f "$RAT_ROOT/pytest.ini" ] || [ -d "$RAT_ROOT/tests" ]; } && command -v pytest >/dev/null 2>&1; then
    echo "pytest -q"
  elif [ -f "$RAT_ROOT/Cargo.toml" ]; then
    echo "cargo test --quiet"
  elif [ -x "$RAT_ROOT/tests/smoke.sh" ]; then
    echo "tests/smoke.sh"
  else
    echo ""
  fi
}

CMD="$(detect_test_cmd)"

if [ -z "$CMD" ]; then
  echo "**What I found** - no test command I recognise in this repository."
  echo
  echo "I looked for a Makefile \`test\` target, an npm test script, pytest, cargo,"
  echo "and tests/smoke.sh. Set one, or set \`verify:\` in this loop's plan.md, and"
  echo "I will have something to run tomorrow."
  echo
  echo "**What I changed** - nothing."
  exit 0
fi

( cd "$RAT_ROOT" && eval "$CMD" ) > "$RUN_LOG" 2>&1
STATUS=$?

if [ "$STATUS" -eq 0 ]; then
  echo "**What I found** - the suite is green (\`$CMD\`, $(wc -l < "$RUN_LOG" | tr -d ' ') lines of output)."
  echo
  echo "**What I changed** - nothing. Nothing was broken."
  echo
  echo "**What I checked** - \`$CMD\`, exit 0. Full output in tests-before.log."
  printf '{"suite":"green","command":%s}\n' "\"$CMD\"" > "$RAT_RECEIPT/cursor.json"
  exit 0
fi

{
  cat "$RAT_RECEIPT/prompt.md"
  echo
  echo "## The suite is red"
  echo
  echo "Command: \`$CMD\` (exit $STATUS)"
  echo
  echo '```'
  tail -c 12000 "$RUN_LOG"
  echo '```'
  echo
  echo "Fix the first failure only. Then run \`$CMD\` yourself and paste what it printed."
} | rat-agent --tag act

printf '{"suite":"red","command":%s,"exit":%s}\n' "\"$CMD\"" "$STATUS" > "$RAT_RECEIPT/cursor.json"
