#!/usr/bin/env bash
# install.sh - put the rat into a project you already have.
#
#   ./install.sh ~/code/your-project
#
# Copies CONTRACT.md, .claude/loops/, bin/, kill.sh and .mcp.json into the
# target, appends the state/ entries to its .gitignore, and touches nothing
# else. Existing files are never overwritten - it says what it skipped.
set -euo pipefail

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

place() {
  local rel="$1"
  if [ -e "$DEST/$rel" ]; then
    printf '  skip   %s (already there)\n' "$rel"
    skipped=$((skipped + 1))
    return
  fi
  mkdir -p "$(dirname "$DEST/$rel")"
  cp -R "$SRC/$rel" "$DEST/$rel"
  printf '  copy   %s\n' "$rel"
  copied=$((copied + 1))
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
place ".claude/loops"
place "packs"
place "bin"
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
echo "copied $copied, skipped $skipped"
echo
echo "next:"
echo "  cd $DEST"
echo "  bin/rat doctor"
echo "  bin/rat add --list               # loops you can install without writing one"
echo "  \$EDITOR CONTRACT.md              # the rules are yours, not mine"
echo "  \$EDITOR .claude/loops/schedule.yml"
echo "  bin/shift digest --dry-run"
