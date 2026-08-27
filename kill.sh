#!/usr/bin/env bash
# kill.sh - the panic file.
#
#   ./kill.sh                 stop everything now, and keep it stopped
#   ./kill.sh "reason here"   same, with a note for the morning
#
# It does two things: kills whatever is running, and writes state/HALT so the
# next scheduled shift refuses to start. Nothing runs again until someone types
# `bin/rat resume`. Reversible on purpose - a panic button you are afraid to
# press is not a panic button.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/lib/common.sh
. "$HERE/bin/lib/common.sh"

REASON="${1:-stopped by hand}"
mkdir -p "$RAT_STATE_DIR"

printf 'HALTED %s by %s: %s\n' "$(rat_now_iso)" "${USER:-unknown}" "$REASON" > "$RAT_HALT"

killed=0
if [ -d "$RAT_STATE_DIR/locks" ]; then
  for lock in "$RAT_STATE_DIR"/locks/*.lock; do
    [ -d "$lock" ] || continue
    pid="$(cat "$lock/pid" 2>/dev/null || true)"
    name="$(basename "$lock" .lock)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      pkill -TERM -P "$pid" 2>/dev/null || true
      kill -TERM "$pid" 2>/dev/null || true
      sleep 2
      kill -KILL "$pid" 2>/dev/null || true
      killed=$((killed + 1))
      printf 'killed %s (pid %s)\n' "$name" "$pid"
    fi
    rm -rf "$lock"
  done
fi

rat_trace halt ok "killed=$killed reason=$REASON"

printf '\nHALTED. %s shift(s) stopped.\n' "$killed"
printf 'Scheduled shifts will refuse to start until you run: bin/rat resume\n'
printf 'What was running is still in state/receipts - nothing was thrown away.\n'
