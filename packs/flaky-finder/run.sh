#!/usr/bin/env bash
# run.sh - run the same command several times and record what changed.
#
# Configure with FLAKY_COMMAND and FLAKY_RUNS in the environment, or leave them
# and it will use the repository's own test command.
set -uo pipefail

RUNS="${FLAKY_RUNS:-5}"
CMD="${FLAKY_COMMAND:-}"

if [ -z "$CMD" ]; then
  if [ -f "$RAT_ROOT/Makefile" ] && grep -qE '^test:' "$RAT_ROOT/Makefile"; then
    CMD="make test"
  elif [ -f "$RAT_ROOT/package.json" ] && grep -q '"test"' "$RAT_ROOT/package.json"; then
    CMD="npm test --silent"
  elif command -v pytest >/dev/null 2>&1 && [ -d "$RAT_ROOT/tests" ]; then
    CMD="pytest -q"
  fi
fi

if [ -z "$CMD" ]; then
  echo "no test command found - set FLAKY_COMMAND in the environment"
  echo "run-count: 0"
  exit 0
fi

echo "### command"
echo "\`$CMD\`, $RUNS runs"
echo

PASSED=0
FAILED=0
for i in $(seq 1 "$RUNS"); do
  if ( cd "${RAT_WORKDIR:-$RAT_ROOT}" && eval "$CMD" ) > "$RAT_RECEIPT/run-$i.log" 2>&1; then
    echo "- run $i: passed"
    PASSED=$((PASSED + 1))
  else
    echo "- run $i: FAILED"
    FAILED=$((FAILED + 1))
    echo '```'
    grep -iE "fail|error|assert" "$RAT_RECEIPT/run-$i.log" | head -n 8
    echo '```'
  fi
done

echo
echo "### summary"
echo "$PASSED passed, $FAILED failed, out of $RUNS"
echo
echo "run-count: $RUNS"
echo "disagreements: $([ "$PASSED" -gt 0 ] && [ "$FAILED" -gt 0 ] && echo 1 || echo 0)"
