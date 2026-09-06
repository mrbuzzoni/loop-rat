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
      rat_kill_tree "$pid" TERM
      # A shift that has been asked to stop still has a receipt to write, and
      # writing one takes a handful of processes. A flat two seconds was a guess
      # that held on a quiet laptop and failed on a loaded machine, where the
      # hard kill landed first and threw away the very thing the line below
      # promises was kept. Wait for the shift to go, and force it only if it
      # will not.
      grace="$(rat_setting caps.kill_grace_seconds 15)"
      case "$grace" in ''|*[!0-9]*) grace=15 ;; esac
      waited=0
      while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$grace" ]; do
        sleep 1
        waited=$((waited + 1))
      done
      if kill -0 "$pid" 2>/dev/null; then
        rat_kill_tree "$pid" KILL
        printf 'killed %s (pid %s) - it did not stop in %ss, so there may be no receipt\n' \
          "$name" "$pid" "$grace"
      else
        printf 'stopped %s (pid %s) after %ss - its receipt was written\n' \
          "$name" "$pid" "$waited"
      fi
      killed=$((killed + 1))
    fi
    rm -rf "$lock"
  done
fi

rat_trace halt ok "killed=$killed reason=$REASON"

printf '\nHALTED. %s shift(s) stopped.\n' "$killed"
printf 'Scheduled shifts will refuse to start until you run: bin/rat resume\n'
printf 'What was running is still in state/receipts - nothing was thrown away.\n'
