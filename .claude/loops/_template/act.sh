#!/usr/bin/env bash
# act.sh - the actual work for the __NAME__ loop.
#
# Available to you:
#   $RAT_ROOT      repository root
#   $RAT_LOOP      this loop's name
#   $RAT_RECEIPT   this shift's receipt folder - write anything you want kept
#   the composed brief is at $RAT_RECEIPT/prompt.md
#   rat-agent      pipe a prompt in, get the model's answer out
#
# stdout becomes output.md in the receipt. stderr becomes stderr.log.
set -uo pipefail

FACTS="$RAT_RECEIPT/facts.md"

{
  echo "### collected $(date -u +%H:%M:%SZ)"
  # Gather here. Anything deterministic belongs in this block, not in the prompt.
  git -C "$RAT_ROOT" log -5 --pretty='%h %s (%cr)' 2>/dev/null || echo "(not a git repo)"
} > "$FACTS"

{
  cat "$RAT_RECEIPT/prompt.md"
  echo
  echo "## The facts, collected before you woke up"
  echo
  cat "$FACTS"
} | rat-agent --tag act
