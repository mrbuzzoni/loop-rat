# Shared helpers for the loop rat harness. Sourced, never executed.
# shellcheck shell=bash

set -o pipefail

rat_root() {
  # Walk up from this file until we find the harness marker.
  local dir="${BASH_SOURCE[0]}"
  dir="$(cd "$(dirname "$dir")/../.." && pwd)"
  printf '%s' "$dir"
}

# Always resolved from this file's own location, never inherited. A shift runs
# child processes that source this file again; if they trusted an inherited
# RAT_ROOT, a harness running inside another harness would write its receipts -
# and point its kill switch - at the wrong repository.
RAT_ROOT="$(rat_root)"
export RAT_ROOT
RAT_LOOPS_DIR="$RAT_ROOT/.claude/loops"
RAT_STATE_DIR="$RAT_ROOT/state"
RAT_SETTINGS="$RAT_LOOPS_DIR/settings.json"
RAT_TRACE="$RAT_STATE_DIR/trace.log"
RAT_CHECKPOINT="$RAT_STATE_DIR/checkpoint.json"
RAT_BUDGET="$RAT_STATE_DIR/budget.json"
RAT_HALT="$RAT_STATE_DIR/HALT"
RAT_CONF="$RAT_ROOT/bin/lib/conf.py"

rat_py() { python3 "$@"; }

rat_now_iso()  { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
rat_today()    { date +"%Y-%m-%d"; }
rat_epoch()    { date +%s; }

rat_color() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then printf '\033[%sm' "$1"; fi
}
rat_say()  { printf '%s%s%s\n' "$(rat_color 2)" "$1" "$(rat_color 0)"; }
rat_warn() { printf '%s%s%s\n' "$(rat_color 33)" "$1" "$(rat_color 0)" >&2; }
rat_err()  { printf '%s%s%s\n' "$(rat_color 31)" "$1" "$(rat_color 0)" >&2; }

# settings.json lookup with a default: rat_setting caps.timeout_seconds 900
rat_setting() {
  local key="$1"
  local fallback="${2:-}"
  local value
  value="$(rat_py "$RAT_CONF" get "$RAT_SETTINGS" "$key" 2>/dev/null || true)"
  if [ -z "$value" ]; then printf '%s' "$fallback"; else printf '%s' "$value"; fi
}

# One line per phase, append-only. This file is the thing you read when a shift
# surprises you.
rat_trace() {
  mkdir -p "$RAT_STATE_DIR"
  printf '%s loop=%s shift=%s phase=%s status=%s %s\n' \
    "$(rat_now_iso)" "${RAT_LOOP:-harness}" "${RAT_SHIFT_ID:--}" "$1" "$2" "${3:-}" \
    >> "$RAT_TRACE"
}

rat_halted() { [ -f "$RAT_HALT" ]; }

# Portable timeout: macOS ships no `timeout` binary, so we run a watchdog.
rat_run_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  (
    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$waited" -ge "$secs" ]; then
        # Children first: act.sh usually has a model call in flight, and killing
        # only the script would leave that process running with nobody waiting.
        pkill -TERM -P "$pid" 2>/dev/null || true
        kill -TERM "$pid" 2>/dev/null
        sleep 3
        pkill -KILL -P "$pid" 2>/dev/null || true
        kill -KILL "$pid" 2>/dev/null
        exit 0
      fi
      sleep 1
      waited=$((waited + 1))
    done
  ) &
  local watchdog=$!
  local rc=0
  wait "$pid" || rc=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  return "$rc"
}

# mkdir is atomic, so it is the lock. A stale lock older than the timeout is
# cleared rather than blocking the next shift forever.
rat_lock() {
  local name="$1"
  local timeout="${2:-3600}"
  local lock="$RAT_STATE_DIR/locks/$name.lock"
  mkdir -p "$RAT_STATE_DIR/locks"
  if mkdir "$lock" 2>/dev/null; then
    printf '%s\n' "$$" > "$lock/pid"
    printf '%s\n' "$(rat_epoch)" > "$lock/started"
    return 0
  fi
  local started age
  started="$(cat "$lock/started" 2>/dev/null || echo 0)"
  age=$(( $(rat_epoch) - started ))
  if [ "$age" -gt "$timeout" ]; then
    rat_warn "clearing stale lock for $name (${age}s old)"
    rm -rf "$lock"
    rat_lock "$name" "$timeout"
    return $?
  fi
  return 1
}

rat_unlock() { rm -rf "$RAT_STATE_DIR/locks/$1.lock"; }

# Short-lived mutual exclusion for the files two loops can write at the same
# moment - the ledger and the checkpoint. Waits a few seconds, then gives up and
# writes anyway: losing one cost entry is better than losing a whole shift.
rat_with_lock() {
  local name="$1"; shift
  local lock="$RAT_STATE_DIR/locks/$name.lock"
  local waited=0
  mkdir -p "$RAT_STATE_DIR/locks"
  while ! mkdir "$lock" 2>/dev/null; do
    waited=$((waited + 1))
    if [ "$waited" -gt 50 ]; then
      rat_warn "gave up waiting for the $name lock"
      break
    fi
    sleep 0.1
  done
  "$@"
  local rc=$?
  rm -rf "$lock"
  return "$rc"
}

# Spend ledger, one bucket per day. Refuses to start a shift once the day's cap
# is gone - the cheapest way to stop a runaway loop is to run out of allowance.
rat_budget_today() {
  rat_py - "$RAT_BUDGET" "$(rat_today)" <<'PY'
import json, os, sys
path, day = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except ValueError:
        data = {}
print("%.4f" % float(data.get("days", {}).get(day, 0.0)))
PY
}

rat_budget_add() {
  local amount="$1"
  local loop="${2:-unknown}"
  mkdir -p "$RAT_STATE_DIR"
  rat_with_lock budget _rat_budget_write "$amount" "$loop"
}

_rat_budget_write() {
  local amount="$1"
  local loop="$2"
  rat_py - "$RAT_BUDGET" "$(rat_today)" "$amount" "$loop" <<'PY'
import json, os, sys
path, day, amount, loop = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
data = {"days": {}, "by_loop": {}}
if os.path.exists(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except ValueError:
        pass
data.setdefault("days", {})
data.setdefault("by_loop", {})
data["days"][day] = round(float(data["days"].get(day, 0.0)) + amount, 4)
data["by_loop"][loop] = round(float(data["by_loop"].get(loop, 0.0)) + amount, 4)
with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
}

rat_json_field() {
  local file="$1"
  local key="$2"
  local fallback="${3:-}"
  rat_py "$RAT_CONF" get "$file" "$key" 2>/dev/null || printf '%s' "$fallback"
}
