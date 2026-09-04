#!/usr/bin/env bash
# check.sh - can this project be installed and built from a clean checkout?
#
# Runs only steps the project already declares. Override the guesses with
# BUILD_INSTALL, BUILD_BUILD and BUILD_SMOKE in the environment.
set -uo pipefail

WORK="${RAT_WORKDIR:-$RAT_ROOT}"
cd "$WORK" || exit 1

INSTALL="${BUILD_INSTALL:-}"
BUILD="${BUILD_BUILD:-}"
SMOKE="${BUILD_SMOKE:-}"

has_script() {
  [ -f package.json ] && python3 - "$1" <<'PY'
import json, sys
try:
    scripts = json.load(open("package.json")).get("scripts", {})
except Exception:
    scripts = {}
raise SystemExit(0 if sys.argv[1] in scripts else 1)
PY
}

if [ -z "$INSTALL" ]; then
  if [ -f package-lock.json ]; then INSTALL="npm ci"
  elif [ -f yarn.lock ]; then INSTALL="yarn install --frozen-lockfile"
  elif [ -f pnpm-lock.yaml ]; then INSTALL="pnpm install --frozen-lockfile"
  elif [ -f package.json ]; then INSTALL="npm install"
  elif [ -f requirements.txt ]; then INSTALL="python3 -m pip install --quiet -r requirements.txt"
  elif [ -f pyproject.toml ]; then INSTALL="python3 -m pip install --quiet ."
  elif [ -f go.mod ]; then INSTALL="go mod download"
  elif [ -f Cargo.toml ]; then INSTALL="cargo fetch"
  fi
fi

if [ -z "$BUILD" ]; then
  if has_script build; then BUILD="npm run build"
  elif [ -f Makefile ] && grep -qE '^build:' Makefile; then BUILD="make build"
  elif [ -f go.mod ]; then BUILD="go build ./..."
  elif [ -f Cargo.toml ]; then BUILD="cargo build --quiet"
  fi
fi

if [ -z "$SMOKE" ]; then
  if has_script test; then SMOKE="npm test --silent"
  elif [ -f Makefile ] && grep -qE '^test:' Makefile; then SMOKE="make test"
  elif [ -d tests ] && command -v pytest >/dev/null 2>&1; then SMOKE="pytest -q"
  fi
fi

if [ -z "$INSTALL$BUILD$SMOKE" ]; then
  echo "### nothing to check"
  echo
  echo "No install, build or test step was found in this project. Set"
  echo "BUILD_INSTALL, BUILD_BUILD or BUILD_SMOKE if there is one worth running."
  echo
  echo "failed-step: none"
  exit 0
fi

echo "### the clean checkout"
echo "commit: $(git -C "$WORK" log -1 --format='%h %s' 2>/dev/null || echo unknown)"
echo

FAILED=""
run_step() {
  local label="$1"
  local command="$2"
  [ -n "$command" ] || return 0
  [ -n "$FAILED" ] && { echo "- $label: skipped, an earlier step failed"; return 0; }

  local log="$RAT_RECEIPT/step-$label.log"
  if eval "$command" > "$log" 2>&1; then
    echo "- $label: passed  (\`$command\`)"
  else
    echo "- $label: FAILED  (\`$command\`)"
    echo '```'
    tail -n 25 "$log"
    echo '```'
    FAILED="$label"
  fi
}

run_step install "$INSTALL"
run_step build "$BUILD"
run_step smoke "$SMOKE"

echo
echo "failed-step: ${FAILED:-none}"
