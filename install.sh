#!/usr/bin/env bash
# install.sh - put the rat into a project you already have.
#
#   ./install.sh ~/code/your-project
#
# Copies CONTRACT.md, .claude/loops/, bin/, kill.sh and .mcp.json into the
# target, appends the state/ entries to its .gitignore, and touches nothing
# else. Existing files are never overwritten - it says what it skipped.
# Not -e: one missing optional file should not abandon an install halfway.
set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-}"

if [ -z "$DEST" ]; then
  echo "usage: ./install.sh <path-to-project>"
  exit 2
fi
if [ ! -d "$DEST" ]; then
  echo "no such directory: $DEST"
  exit 1
fi

DEST="$(cd "$DEST" && pwd)"
if [ "$DEST" = "$SRC" ]; then
  echo "that is where the rat already lives"
  exit 1
fi

copied=0
skipped=0
failed=0

place() {
  local rel="$1"
  if [ -e "$DEST/$rel" ]; then
    printf '  skip   %s (already there)\n' "$rel"
    skipped=$((skipped + 1))
    return 0
  fi
  # A missing optional file is not a reason to abandon the install halfway and
  # leave someone with half a harness.
  if [ ! -e "$SRC/$rel" ]; then
    printf '  skip   %s (not in this copy)\n' "$rel"
    skipped=$((skipped + 1))
    return 0
  fi
  mkdir -p "$(dirname "$DEST/$rel")"
  if cp -R "$SRC/$rel" "$DEST/$rel"; then
    printf '  copy   %s\n' "$rel"
    copied=$((copied + 1))
  else
    printf '  FAIL   %s could not be copied\n' "$rel"
    failed=$((failed + 1))
  fi
  return 0
}

# `state/` is a common directory name. If the target already uses it for
# something of its own, say so before writing receipts into it.
if [ -d "$DEST/state" ] && [ -n "$(ls -A "$DEST/state" 2>/dev/null)" ]; then
  echo "warning: $DEST/state already exists and is not empty."
  echo "         The rat writes receipts, locks and the halt file there."
  echo "         Move that directory, or change RAT_STATE_DIR in bin/lib/common.sh,"
  echo "         before you schedule anything."
  echo
fi

echo "installing into $DEST"
place "CONTRACT.md"
place "contract.local.example.md"
place "bin"
place "packs"

# The loops, minus the ones that only make sense inside this repository, and
# minus a schedule that would be about someone else's project. `rat init` writes
# a schedule for yours.
mkdir -p "$DEST/.claude/loops"
for part in rubrics _template digest test-mender pr-hunter cost-watch; do
  if [ ! -e "$DEST/.claude/loops/$part" ] && [ -e "$SRC/.claude/loops/$part" ]; then
    cp -R "$SRC/.claude/loops/$part" "$DEST/.claude/loops/$part"
    printf '  copy   .claude/loops/%s\n' "$part"
    copied=$((copied + 1))
  fi
done
if [ ! -e "$DEST/.claude/loops/settings.json" ]; then
  cp "$SRC/.claude/loops/settings.json" "$DEST/.claude/loops/settings.json"
  printf '  copy   .claude/loops/settings.json\n'
fi
if [ ! -e "$DEST/.claude/loops/schedule.yml" ]; then
  cat > "$DEST/.claude/loops/schedule.yml" <<'PLACEHOLDER'
# placeholder - nothing is scheduled yet, on purpose.
#
# Run `bin/rat init` and this file is replaced with a schedule that fits this
# project. Until then no loop will ever start on its own.

loops: []
PLACEHOLDER
  printf '  wrote  .claude/loops/schedule.yml (empty until you run rat init)\n'
fi
place "kill.sh"
place ".mcp.json"
mkdir -p "$DEST/state"
cp "$SRC/state/.gitkeep" "$DEST/state/.gitkeep" 2>/dev/null || true

# Deliberately explicit rather than `state/*`: the target repository may already
# track files under a directory of that name, and an installer has no business
# hiding them.
IGNORE_BLOCK='
# loop rat
contract.local.md
state/receipts/
state/digest/
state/locks/
state/scratch/
state/trace.log
state/budget.json
state/checkpoint.json
state/cron.log
state/HALT'

if [ -f "$DEST/.gitignore" ] && grep -q "^# loop rat" "$DEST/.gitignore"; then
  printf '  skip   .gitignore (already has the block)\n'
else
  printf '%s\n' "$IGNORE_BLOCK" >> "$DEST/.gitignore"
  printf '  patch  .gitignore\n'
fi

echo
if [ "$failed" -gt 0 ]; then
  echo "copied $copied, skipped $skipped, FAILED $failed - the install is incomplete"
else
  echo "copied $copied, skipped $skipped"
fi
echo
echo "next:"
echo "  cd $DEST"
echo "  bin/rat init                     # loops and a schedule that fit this project"
echo "  bin/rat doctor"
echo "  \$EDITOR CONTRACT.md              # the rules are yours, not mine"
echo "  \$EDITOR .claude/loops/schedule.yml"
echo "  bin/shift digest --dry-run"
