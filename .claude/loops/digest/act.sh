#!/usr/bin/env bash
# act.sh - gather last night's receipts, ask for one page of prose.
set -uo pipefail

SUMMARY="$RAT_RECEIPT/last-24h.md"
OUT_DIR="$RAT_ROOT/state/digest"
mkdir -p "$OUT_DIR"

python3 - "$RAT_ROOT/state/receipts" > "$SUMMARY" <<'PY'
import json, os, sys, time

root = sys.argv[1]
cutoff = time.time() - 24 * 3600
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
    print("No shift produced a receipt in the last 24 hours.")
    raise SystemExit(0)

total = sum(float(r[1].get("cost_usd", 0) or 0) for r in rows)
print("%d shifts, $%.2f spent." % (len(rows), total))
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
  echo "## Last 24 hours, from the receipts"
  echo
  cat "$SUMMARY"
} | rat-agent --tag act | tee "$OUT_DIR/$(date +%Y-%m-%d).md"
STATUS=$?

printf '{"digest":"%s"}\n' "state/digest/$(date +%Y-%m-%d).md" > "$RAT_RECEIPT/cursor.json"
exit "$STATUS"
