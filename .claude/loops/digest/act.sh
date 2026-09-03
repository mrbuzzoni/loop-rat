#!/usr/bin/env bash
# act.sh - gather last night's receipts, ask for one page of prose.
set -uo pipefail

# Mondays get the week. A single night tells you what happened; seven tell you
# whether a loop is drifting, and drift is the thing you cannot see one night at
# a time.
if [ "$(date +%u)" = "1" ]; then
  WINDOW_HOURS=168
  WINDOW_NAME="week"
else
  WINDOW_HOURS=24
  WINDOW_NAME="night"
fi
SUMMARY="$RAT_RECEIPT/last-$WINDOW_HOURS-hours.md"
OUT_DIR="$RAT_ROOT/state/digest"
mkdir -p "$OUT_DIR"

python3 - "$RAT_ROOT/state/receipts" "$WINDOW_HOURS" > "$SUMMARY" <<'PY'
import json, os, sys, time

root = sys.argv[1]
hours = int(sys.argv[2])
cutoff = time.time() - hours * 3600
rows = []
for dirpath, _dirnames, filenames in os.walk(root):
    if "receipt.json" not in filenames:
        continue
    path = os.path.join(dirpath, "receipt.json")
    if os.path.getmtime(path) < cutoff:
        continue
    try:
        with open(path) as fh:
            rows.append((path, json.load(fh)))
    except ValueError:
        continue

rows.sort(key=lambda r: r[1].get("started", ""))
if not rows:
    print("No shift produced a receipt in the last %d hours." % hours)
    raise SystemExit(0)

total = sum(float(r[1].get("cost_usd", 0) or 0) for r in rows)
print("%d shifts over %d hours, $%.2f spent." % (len(rows), hours, total))
print()
for path, r in rows:
    folder = os.path.dirname(path)
    print("### %s  %s  verdict=%s  %ss  $%.4f" % (
        r.get("started", "")[:16], r.get("loop", "?"), r.get("verdict", "?"),
        r.get("duration_seconds", 0), float(r.get("cost_usd", 0) or 0)))
    verify = r.get("verify", {})
    if verify.get("status") not in (None, "skipped"):
        print("verify: %s" % verify["status"])
    guard = r.get("guard", {})
    if guard.get("status") != "ok" or guard.get("files_changed"):
        print("guard: %s, %s file(s) changed" % (guard.get("status"), guard.get("files_changed")))
    grade_path = os.path.join(folder, "grade.json")
    if os.path.exists(grade_path):
        try:
            with open(grade_path) as fh:
                grade = json.load(fh)
            print("grade: %s - %s" % (grade.get("verdict"), grade.get("notes", "")))
        except ValueError:
            pass
    out_path = os.path.join(folder, "output.md")
    if os.path.exists(out_path):
        with open(out_path) as fh:
            body = fh.read(1200).strip()
        print("report:")
        print(body)
    print()
PY

{
  cat "$RAT_RECEIPT/prompt.md"
  echo
  echo "## The last $WINDOW_HOURS hours, from the receipts"
  echo
  cat "$SUMMARY"
  echo
  echo "You are writing the $WINDOW_NAME digest."
} | rat-agent --tag act | tee "$OUT_DIR/$(date +%Y-%m-%d)-$WINDOW_NAME.md"
STATUS=$?

printf '{"digest":"%s","window_hours":%s}\n' \
  "state/digest/$(date +%Y-%m-%d)-$WINDOW_NAME.md" "$WINDOW_HOURS" > "$RAT_RECEIPT/cursor.json"
exit "$STATUS"
