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

# Windows installs Python as `python`; most everywhere else it is `python3`, and
# on a few machines `python` is still a 2.x. Ask, once, rather than assuming.
# Answered once, here, rather than inside a function that everything calls from
# a `$( )` - a subshell cannot hand a variable back to its parent, so a cache
# filled in one is a cache refilled every single time.
rat_python_detect() {
  [ -n "${RAT_PYTHON:-}" ] && return 0
  local candidate
  for candidate in python3 python py; do
    if command -v "$candidate" >/dev/null 2>&1 &&
       "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)' 2>/dev/null; then
      RAT_PYTHON="$candidate"
      export RAT_PYTHON
      return 0
    fi
  done
  RAT_PYTHON="python3"
  export RAT_PYTHON
  return 1
}

rat_python() { printf '%s' "${RAT_PYTHON:-python3}"; }
rat_py() { "${RAT_PYTHON:-python3}" "$@"; }

# msys and cygwin are how a Windows machine usually gets here: Git Bash. WSL
# reports linux and needs nothing special.
rat_os() {
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin) printf 'macos' ;;
    Linux) printf 'linux' ;;
    MINGW*|MSYS*|CYGWIN*) printf 'windows' ;;
    *) printf 'unknown' ;;
  esac
}

rat_now_iso()  { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
rat_today()    { date +"%Y-%m-%d"; }
rat_epoch()    { date +%s; }

rat_color() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then printf '\033[%sm' "$1"; fi
}
rat_say()  { printf '%s%s%s\n' "$(rat_color 2)" "$1" "$(rat_color 0)"; }
rat_warn() { printf '%s%s%s\n' "$(rat_color 33)" "$1" "$(rat_color 0)" >&2; }
rat_err()  { printf '%s%s%s\n' "$(rat_color 31)" "$1" "$(rat_color 0)" >&2; }

# Every setting, read once, into shell variables. A shift asks for two dozen of
# them, and a python process per question was most of what a dry run spent its
# time doing.
rat_settings_load() {
  [ "${RAT_SETTINGS_LOADED:-}" = "$RAT_SETTINGS" ] && return 0
  local dump
  dump="$(rat_py "$RAT_ROOT/bin/lib/flatten.py" json "$RAT_SETTINGS" RAT_S_ 2>/dev/null)" || dump=""
  eval "$dump"
  RAT_SETTINGS_LOADED="$RAT_SETTINGS"
  export RAT_SETTINGS_LOADED
}

# settings.json lookup with a default: rat_setting caps.timeout_seconds 900
rat_setting() {
  local key="$1"
  local fallback="${2:-}"
  [ "${RAT_SETTINGS_LOADED:-}" = "$RAT_SETTINGS" ] || rat_settings_load
  local name="RAT_S_$(printf '%s' "$key" | tr -c 'A-Za-z0-9' '_')"
  local value="${!name:-}"
  if [ -z "$value" ]; then printf '%s' "$fallback"; else printf '%s' "$value"; fi
}

# The same trick for a plan's front matter, which a shift reads eight times.
rat_plan_load() {
  local plan="$1"
  [ "${RAT_PLAN_LOADED:-}" = "$plan" ] && return 0
  local dump
  dump="$(rat_py "$RAT_ROOT/bin/lib/flatten.py" front-matter "$plan" RAT_P_ 2>/dev/null)" || dump=""
  eval "$dump"
  RAT_PLAN_LOADED="$plan"
  export RAT_PLAN_LOADED
}

rat_plan() {
  local plan="$1"
  local key="$2"
  local fallback="${3:-}"
  rat_plan_load "$plan"
  local name="RAT_P_$(printf '%s' "$key" | tr -c 'A-Za-z0-9' '_')"
  local value="${!name:-}"
  if [ -z "$value" ]; then printf '%s' "$fallback"; else printf '%s' "$value"; fi
}

# Whatever this machine has. python3 is the floor we already depend on, so the
# chain works even on a box with neither shasum nor sha256sum.
rat_hash() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -c1-16
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -c1-16
  else
    rat_py -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:16])'
  fi
}

# One line per phase, append-only, and each line carries the hash of the line
# before it. Editing or deleting a line breaks every hash after it, so the log
# is not just a record - it is a record that says whether it has been edited.
# `rat audit` is what checks it.
rat_trace() {
  mkdir -p "$RAT_STATE_DIR"
  rat_with_lock trace _rat_trace_write "$@"
}

_rat_trace_write() {
  local line
  line="$(printf '%s loop=%s shift=%s phase=%s status=%s %s' \
    "$(rat_now_iso)" "${RAT_LOOP:-harness}" "${RAT_SHIFT_ID:--}" "$1" "$2" "${3:-}")"
  local prev=""
  if [ -f "$RAT_TRACE" ]; then
    prev="$(tail -n 1 "$RAT_TRACE" 2>/dev/null | sed -n 's/.* h=\([0-9a-f]*\)$/\1/p')"
  fi
  local digest
  digest="$(printf '%s|%s' "$prev" "$line" | rat_hash)"
  printf '%s h=%s\n' "$line" "$digest" >> "$RAT_TRACE"
}

rat_halted() { [ -f "$RAT_HALT" ]; }

# Portable timeout: macOS ships no `timeout` binary, so we run a watchdog.
rat_run_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  RAT_CHILD_PID="$pid"
  (
    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$waited" -ge "$secs" ]; then
        rat_kill_tree "$pid" TERM
        sleep 3
        rat_kill_tree "$pid" KILL
        exit 0
      fi
      sleep 1
      waited=$((waited + 1))
    done
  ) &
  local watchdog=$!
  local rc=0
  wait "$pid" || rc=$?
  RAT_CHILD_PID=""
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  return "$rc"
}

# Kill a process and whatever it started. act.sh usually has a model call in
# flight, and killing only the script leaves that call running with nobody
# waiting for it.
#
# There is no portable way to do this: pkill knows about parents on unix,
# taskkill knows about trees on Windows, and Git Bash has neither pkill nor a
# usable process group. So: try each, in the order most likely to work here.
rat_kill_tree() {
  local pid="$1"
  local signal="${2:-TERM}"
  [ -n "$pid" ] || return 0

  if command -v pkill >/dev/null 2>&1; then
    pkill "-$signal" -P "$pid" 2>/dev/null || true
  elif command -v taskkill >/dev/null 2>&1; then
    # /T takes the whole tree, which is what the unix branch approximates.
    if [ "$signal" = "KILL" ]; then
      taskkill //PID "$pid" //T //F >/dev/null 2>&1 || true
    else
      taskkill //PID "$pid" //T >/dev/null 2>&1 || true
    fi
  else
    # Last resort: ask the children who their parent is.
    local child
    for child in $(rat_py -c '
import subprocess, sys
parent = sys.argv[1]
try:
    out = subprocess.run(["ps", "-o", "pid=,ppid="], capture_output=True, text=True).stdout
except OSError:
    raise SystemExit(0)
for line in out.splitlines():
    parts = line.split()
    if len(parts) == 2 and parts[1] == parent:
        print(parts[0])
' "$pid" 2>/dev/null); do
      kill "-$signal" "$child" 2>/dev/null || true
    done
  fi

  kill "-$signal" "$pid" 2>/dev/null || true
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
  local holder
  holder="$(cat "$lock/pid" 2>/dev/null || true)"
  if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
    rat_warn "clearing lock for $name - pid $holder is gone"
    rm -rf "$lock"
    rat_lock "$name" "$timeout"
    return $?
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
  # Not "<name>.lock": kill.sh treats those as shifts to stop. A mutex is held
  # for milliseconds and has no pid worth killing.
  local lock="$RAT_STATE_DIR/locks/mutex-$name"
  local waited=0
  mkdir -p "$RAT_STATE_DIR/locks"
  while ! mkdir "$lock" 2>/dev/null; do
    waited=$((waited + 1))
    if [ "$waited" -gt 50 ]; then
      # Five seconds is far longer than any holder needs. A mutex this old was
      # left by a process that died holding it.
      rm -rf "$lock"
      continue
    fi
    sleep 0.1
  done
  "$@"
  local rc=$?
  rm -rf "$lock"
  return "$rc"
}

# On a subscription the dollar figure a CLI reports is notional - what you
# actually spend is calls against your own quota, and a schedule that eats it is
# a schedule you turn off. So the ledger counts both.
rat_calls_today() {
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
print(int(data.get("calls", {}).get(day, 0)))
PY
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
  local calls="${3:-0}"
  mkdir -p "$RAT_STATE_DIR"
  rat_with_lock budget _rat_budget_write "$amount" "$loop" "$calls"
}

_rat_budget_write() {
  local amount="$1"
  local loop="$2"
  local calls="${3:-0}"
  rat_py - "$RAT_BUDGET" "$(rat_today)" "$amount" "$loop" "$calls" <<'PY'
import json, os, sys
path, day, amount, loop = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
calls = int(sys.argv[5]) if len(sys.argv) > 5 else 0
data = {"days": {}, "by_loop": {}, "calls": {}}
if os.path.exists(path):
    try:
        with open(path) as fh:
            data = json.load(fh)
    except ValueError:
        pass
data.setdefault("days", {})
data.setdefault("by_loop", {})
data.setdefault("calls", {})
data["days"][day] = round(float(data["days"].get(day, 0.0)) + amount, 4)
data["by_loop"][loop] = round(float(data["by_loop"].get(loop, 0.0)) + amount, 4)
data["calls"][day] = int(data["calls"].get(day, 0)) + calls
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

# Read the machine and the settings once, at the moment this file is sourced, so
# that every subshell below inherits the answers instead of working them out
# again.
rat_python_detect
rat_settings_load
