#!/usr/bin/env bash
# smoke.sh - proves the rat works without spending a cent.
#
# Copies the harness into a scratch directory and runs every phase there for
# real: locks, timeouts, the guard, receipts, the checkpoint, the budget ledger,
# the kill switch. Only the model call is stubbed. If this passes, the one thing
# left untested is the model's judgment.
#
#   tests/smoke.sh
set -u

# Never inherit a parent harness's environment: this test must act on its own
# scratch copy and nothing else.
unset RAT_ROOT RAT_LOOP RAT_SHIFT_ID RAT_RECEIPT RAT_DRY_RUN RAT_PLAN RAT_TIMEOUT RAT_MAX_USD

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB="$(mktemp -d)"
trap 'rm -rf "$LAB"' EXIT

cp -R "$SRC/bin" "$SRC/.claude" "$SRC/packs" "$SRC/CONTRACT.md" "$SRC/kill.sh" "$LAB/"
mkdir -p "$LAB/tests"
cp "$SRC/tests/at_rule.py" "$LAB/tests/"
mkdir -p "$LAB/state"
cd "$LAB"
git init -q . 2>/dev/null
printf 'state/\n' > .gitignore
printf 'original\n' > app.txt
git -C "$LAB" add -A >/dev/null 2>&1
git -C "$LAB" -c user.email=smoke@test -c user.name=smoke commit -qm baseline >/dev/null 2>&1

PASS=0
FAIL=0
pass()    { printf '  ok    %s\n' "$1"; PASS=$((PASS + 1)); }
fail()    { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL + 1)); }
check() {
  local out
  if out="$(eval "$2" 2>&1)"; then
    pass "$1"
  else
    fail "$1"
    [ -n "$out" ] && printf '%s\n' "$out" | head -n 5 | sed 's/^/          /'
  fi
}
section() { printf '\n%s\n' "$1"; }

section "parsers"
check "settings.json is readable"          "python3 bin/lib/conf.py get .claude/loops/settings.json caps.timeout_seconds"
check "plan front matter parses"           "python3 bin/lib/conf.py fm-get .claude/loops/digest/plan.md rubrics | grep -q writing"
check "plan body separates from matter"    "python3 bin/lib/conf.py body .claude/loops/digest/plan.md | grep -q 'reads the other loops'"
check "every scheduled loop is listed"     "test \"\$(python3 bin/lib/schedule.py list .claude/loops/schedule.yml | wc -l | tr -d ' ')\" -ge 3"
check "cron installs one run-due tick"     "test \"\$(python3 bin/lib/schedule.py cron .claude/loops/schedule.yml \"\$PWD\" | grep -c 'bin/rat run-due')\" -eq 1"
check "cron lists the schedule as comments" "python3 bin/lib/schedule.py cron .claude/loops/schedule.yml \"\$PWD\" | grep -q '#   pr-hunter'"
check "a daily at: fires once a day"       "python3 tests/at_rule.py"
printf 'loops:\n  - name: parked\n    every: 1d\n    enabled: false\n' > /tmp/rat-sched.yml
check "a paused loop is reported paused"   "python3 bin/lib/schedule.py list /tmp/rat-sched.yml | grep -q paused"
check "a paused loop is never due"         "test -z \"\$(python3 bin/lib/schedule.py due /tmp/rat-sched.yml /dev/null)\""

section "one dry shift, end to end"
bin/shift digest --dry-run > /tmp/rat-shift.out 2>&1
RC=$?
sed 's/^/        /' /tmp/rat-shift.out
check "the shift finished with a verdict"  "test $RC -eq 0 -o $RC -eq 2"
RECEIPT="$(dirname "$(find state/receipts -name receipt.json 2>/dev/null | sort | tail -n 1)")"
check "a receipt folder exists"            "test -d '$RECEIPT'"
check "receipt.json is valid json"         "python3 -c \"import json;json.load(open('$RECEIPT/receipt.json'))\""
check "the contract reached the prompt"    "grep -q 'What you may never do' '$RECEIPT/prompt.md'"
check "the rubric reached the prompt"      "grep -q 'Rubric: writing' '$RECEIPT/prompt.md'"
check "the plan body reached the prompt"   "grep -q 'The loop that reads the other loops' '$RECEIPT/prompt.md'"
check "stdout was captured as output.md"   "test -s '$RECEIPT/output.md'"
check "the guard ran and wrote json"       "python3 -c \"import json;json.load(open('$RECEIPT/guard.json'))\""
check "the grader wrote a verdict"         "grep -q verdict '$RECEIPT/grade.json'"
check "trace.log recorded every phase"     "grep -q 'phase=act' state/trace.log && grep -q 'phase=guard' state/trace.log && grep -q 'phase=receipt' state/trace.log"
check "the checkpoint remembers the loop"  "python3 bin/lib/conf.py get state/checkpoint.json loops.digest.last_verdict"
check "the cursor survived the shift"      "python3 bin/lib/conf.py get state/checkpoint.json loops.digest.cursor"

section "the guard"
# A loop that misbehaves on purpose. The guard has to notice, and the shift has
# to be blocked before anyone reads the output.
make_bad_loop() {
  local name="$1"
  local autonomy="${3:-assisted}"       # these loops are meant to write; the
  mkdir -p ".claude/loops/$name"        # question is what stops them when they do
  printf -- '---\nname: %s\nautonomy: %s\nrubrics: []\ntimeout: 30\n---\nmisbehave\n' \
    "$name" "$autonomy" > ".claude/loops/$name/plan.md"
  printf '#!/usr/bin/env bash\n%s\necho reported\n' "$2" > ".claude/loops/$name/act.sh"
  chmod +x ".claude/loops/$name/act.sh"
}

make_bad_loop _leaky 'mkdir -p secrets && printf "token=abc\n" > secrets/prod.txt'
bin/shift _leaky --dry-run >/dev/null 2>&1
RC=$?
check "writing to a denied path blocks"    "test \"$RC\" -eq 3"
LEAK_RECEIPT="$(dirname "$(find state/receipts -name 'guard.json' | sort | tail -n 1)")"
check "the violation is named in guard.json" "grep -q denylist '$LEAK_RECEIPT/guard.json'"
check "the block is in the trace"          "grep -q 'phase=guard status=blocked' state/trace.log"
rm -rf secrets .claude/loops/_leaky

make_bad_loop _spray 'for i in $(seq 1 14); do printf "x\n" > "spray-$i.txt"; done'
bin/shift _spray --dry-run >/dev/null 2>&1
RC=$?
check "exceeding the blast radius blocks"  "test \"$RC\" -eq 3"
check "the limit is named in guard.json"   "grep -q blast-radius \"\$(dirname \"\$(find state/receipts -name guard.json | sort | tail -n 1)\")/guard.json\""
rm -f spray-*.txt
rm -rf .claude/loops/_spray

printf 'ordinary work\n' > already-dirty.txt
make_bad_loop _quiet 'true'
bin/shift _quiet --dry-run >/dev/null 2>&1
RC=$?
check "work left on the branch is not blamed" "test \"$RC\" -le 2"
rm -f already-dirty.txt
rm -rf .claude/loops/_quiet

section "the locks"
# The holder has to be alive: a lock whose process is gone is stale by
# definition, and the harness clears it instead of blocking the loop forever.
sleep 30 &
HOLDER=$!
mkdir -p state/locks/digest.lock
date +%s > state/locks/digest.lock/started
echo "$HOLDER" > state/locks/digest.lock/pid
bin/shift digest --dry-run >/dev/null 2>&1
RC=$?
check "a live holder blocks a second shift" "test $RC -eq 75"
kill "$HOLDER" 2>/dev/null
wait "$HOLDER" 2>/dev/null

mkdir -p state/locks/digest.lock
date +%s > state/locks/digest.lock/started
echo 999999 > state/locks/digest.lock/pid
bin/shift digest --dry-run >/dev/null 2>&1
RC=$?
check "a dead holder is cleared, not obeyed" "test $RC -le 2"
rm -rf state/locks/digest.lock

section "the budget"
check "the ledger records a charge"        "bash -c '. bin/lib/common.sh; rat_budget_add 0.25 smoke; test \"\$(rat_budget_today)\" = \"0.2500\"'"
python3 - <<'PY'
import json, datetime
day = datetime.date.today().isoformat()
json.dump({"days": {day: 99.0}, "by_loop": {}}, open("state/budget.json", "w"))
PY
bin/shift digest --dry-run >/dev/null 2>&1
RC=$?
check "a spent day refuses to start"       "test \"$RC\" -eq 75"
rm -f state/budget.json

section "concurrency"
rm -f state/budget.json
for i in 1 2 3 4 5 6 7 8; do
  ( . bin/lib/common.sh && rat_budget_add 0.10 "loop$i" ) &
done
wait
check "eight writers lose no spend"        "python3 -c \"
import json
d = json.load(open('state/budget.json'))
assert abs(list(d['days'].values())[0] - 0.8) < 0.0001, d
assert len(d['by_loop']) == 8, d
\""
rm -f state/budget.json

section "a plan the harness cannot honour"
mkdir -p .claude/loops/_quoted
printf -- '---\nname: _quoted\nrubrics: []\ntimeout: 30\nverify: "echo \\"it works\\"; test 1 -eq 1"\n---\nnothing\n' > .claude/loops/_quoted/plan.md
printf '#!/usr/bin/env bash\necho reported\n' > .claude/loops/_quoted/act.sh
chmod +x .claude/loops/_quoted/act.sh
bin/shift _quoted --dry-run >/dev/null 2>&1
check "a verify command with quotes runs"  "grep -q '\"status\": \"pass\"' \"\$(dirname \"\$(find state/receipts -name receipt.json | sort | tail -n 1)\")/receipt.json\""
rm -rf .claude/loops/_quoted

mv CONTRACT.md CONTRACT.md.away
bin/shift digest --dry-run >/dev/null 2>&1
RC=$?
check "no contract, no shift"              "test \"$RC\" -eq 1"
mv CONTRACT.md.away CONTRACT.md

section "autonomy"
mkdir -p .claude/loops/_reporter
printf -- '---\nname: _reporter\nautonomy: report-only\nrubrics: []\ntimeout: 30\n---\nreport\n' > .claude/loops/_reporter/plan.md
printf '#!/usr/bin/env bash\nprintf "x\\n" > touched-by-a-reporter.txt\necho reported\n' > .claude/loops/_reporter/act.sh
chmod +x .claude/loops/_reporter/act.sh
bin/shift _reporter --dry-run >/dev/null 2>&1
RC=$?
check "a report-only loop may not write" "test $RC -eq 3"
RECEIPT_A="$(dirname "$(find state/receipts -name guard.json | sort | tail -n 1)")"
check "the block names the level"        "grep -q '\"kind\": \"autonomy\"' '$RECEIPT_A/guard.json'"
check "the receipt records the level"    "grep -q '\"autonomy\": \"report-only\"' '$RECEIPT_A/receipt.json'"
check "the brief told the loop the rule" "grep -q 'Your autonomy this shift: report-only' '$RECEIPT_A/prompt.md'"
rm -f touched-by-a-reporter.txt
rm -rf .claude/loops/_reporter

mkdir -p .claude/loops/_helper
printf -- '---\nname: _helper\nautonomy: assisted\nrubrics: []\ntimeout: 30\n---\nhelp\n' > .claude/loops/_helper/plan.md
printf '#!/usr/bin/env bash\nprintf "x\\n" > touched-by-a-helper.txt\necho reported\n' > .claude/loops/_helper/act.sh
chmod +x .claude/loops/_helper/act.sh
bin/shift _helper --dry-run >/dev/null 2>&1
RC=$?
check "an assisted loop may write"       "test $RC -le 2"
rm -f touched-by-a-helper.txt
rm -rf .claude/loops/_helper

mkdir -p .claude/loops/_typo
printf -- '---\nname: _typo\nautonomy: autonmous\nrubrics: []\ntimeout: 30\n---\ntypo\n' > .claude/loops/_typo/plan.md
printf '#!/usr/bin/env bash\nprintf "x\\n" > touched-by-a-typo.txt\necho reported\n' > .claude/loops/_typo/act.sh
chmod +x .claude/loops/_typo/act.sh
bin/shift _typo --dry-run >/dev/null 2>&1
RC=$?
check "a misspelled level is the strictest" "test $RC -eq 3"
rm -f touched-by-a-typo.txt
rm -rf .claude/loops/_typo

mkdir -p .claude/loops/_quiet
printf -- '---\nname: _quiet\nautonomy: report-only\nrubrics: []\ntimeout: 30\n---\nquiet\n' > .claude/loops/_quiet/plan.md
printf '#!/usr/bin/env bash\necho "reported and touched nothing"\n' > .claude/loops/_quiet/act.sh
chmod +x .claude/loops/_quiet/act.sh
bin/shift _quiet --dry-run >/dev/null 2>&1
RC=$?
check "its own receipt is not a change"  "test $RC -le 2"
rm -rf .claude/loops/_quiet

section "watching a shift"
( bin/shift digest --dry-run >/dev/null 2>&1 & ) 
bin/rat watch --timeout 45 > /tmp/rat-watch.out 2>&1
check "watch follows a live shift"       "grep -q 'phase\|preflight' /tmp/rat-watch.out || grep -q digest /tmp/rat-watch.out"
check "watch ends with the receipt"      "grep -q 'full receipt' /tmp/rat-watch.out"
check "watch gives up when nothing runs" "bin/rat watch --timeout 2 >/dev/null 2>&1; test \$? -eq 75"

section "the shipped loops"
bin/shift docs-drift --dry-run >/dev/null 2>&1
RC=$?
check "docs-drift runs end to end"       "test $RC -le 2"
DRIFT_RECEIPT="$(find state/receipts -type d -name '*-docs-drift' | sort | tail -n 1)"
check "a clean scan calls no model"      "grep -q 'no model was called' '$DRIFT_RECEIPT/output.md'"
check "the scan output is kept"          "test -s '$DRIFT_RECEIPT/drift.md'"
bin/shift cost-watch --dry-run >/dev/null 2>&1
RC=$?
check "cost-watch runs end to end"       "test $RC -le 2"
check "cost-watch counted real shifts"   "grep -q 'shifts across' \"\$(dirname \"\$(find state/receipts -name numbers.md | sort | tail -n 1)\")/numbers.md\""

section "the model bridge"
mkdir -p state/scratch
printf '0.9000\n' > state/scratch/agent-prior.cost
RAT_RECEIPT="$PWD/state/scratch" RAT_MAX_USD=0.50 RAT_LOOP=cap-probe \
  bin/rat-agent --tag probe > /tmp/rat-cap.out 2>&1 <<< "anything"
RC=$?
check "a shift past its cap makes no call" "test \"$RC\" -eq 1"
check "and the receipt says why"           "grep -q 'spend cap' /tmp/rat-cap.out"
rm -rf state/scratch

mkdir -p state/scratch
python3 - <<'PY'
import json
path = ".claude/loops/settings.json"
settings = json.load(open(path))
settings["agent"] = {"command": "printf", "args": ["[%s]", "two words"],
                     "result_field": "result", "cost_field": "total_cost_usd"}
json.dump(settings, open("/tmp/rat-settings-argtest.json", "w"), indent=2)
PY
cp .claude/loops/settings.json /tmp/rat-settings-real.json
cp /tmp/rat-settings-argtest.json .claude/loops/settings.json
RAT_RECEIPT="$PWD/state/scratch" RAT_LOOP=arg-probe \
  bin/rat-agent --tag probe > /tmp/rat-args.out 2>&1 <<< "anything"
check "an agent arg with a space stays one" "grep -q '\[two words\]' /tmp/rat-args.out"
cp /tmp/rat-settings-real.json .claude/loops/settings.json
rm -rf state/scratch

section "the kill switch"
./kill.sh "smoke test" >/dev/null 2>&1
check "kill.sh writes state/HALT"          "test -f state/HALT"
bin/shift digest --dry-run >/dev/null 2>&1
RC=$?
check "a halted harness starts nothing"    "test \"$RC\" -eq 75"
check "the halt names who and why"         "grep -q 'smoke test' state/HALT"
bin/rat resume >/dev/null 2>&1
check "resume clears the halt"             "test ! -f state/HALT"

section "timeouts"
mkdir -p .claude/loops/_slow
cat > .claude/loops/_slow/plan.md <<'PLAN'
---
name: _slow
rubrics: []
timeout: 2
---
sleep forever
PLAN
printf '#!/usr/bin/env bash\nsleep 30\n' > .claude/loops/_slow/act.sh
chmod +x .claude/loops/_slow/act.sh
START=$(date +%s)
bin/shift _slow --dry-run >/dev/null 2>&1
ELAPSED=$(( $(date +%s) - START ))
check "a hung shift is killed at its cap"  "test $ELAPSED -lt 15"
check "the timeout is in the trace"        "grep -q 'phase=act status=timeout' state/trace.log"
rm -rf .claude/loops/_slow

section "pruning"
mkdir -p state/receipts/2026-01-01/010101-digest state/receipts/2026-01-02/020202-digest
printf '{"verdict":"pass","loop":"digest"}\n' > state/receipts/2026-01-01/010101-digest/receipt.json
printf '{"verdict":"needs-review","loop":"digest"}\n' > state/receipts/2026-01-02/020202-digest/receipt.json
touch -t 202601010101 state/receipts/2026-01-01/010101-digest
touch -t 202601020202 state/receipts/2026-01-02/020202-digest
check "a dry prune deletes nothing"        "bin/rat prune | grep -q 'would remove' && test -d state/receipts/2026-01-01/010101-digest"
check "--apply removes what aged out"      "bin/rat prune --apply >/dev/null && test ! -d state/receipts/2026-01-01/010101-digest"
mkdir -p state/receipts/2026-01-03/030303-digest
printf '{"verdict":"pass","loop":"digest"}\n' > state/receipts/2026-01-03/030303-digest/receipt.json
touch -t "$(date -v-40d +%Y%m%d%H%M 2>/dev/null || date -d '40 days ago' +%Y%m%d%H%M)" state/receipts/2026-01-03/030303-digest
check "a 40-day pass is pruned"            "bin/rat prune | grep -q 'would remove 1'"
mkdir -p state/receipts/2026-01-04/040404-digest
printf '{"verdict":"blocked","loop":"digest"}\n' > state/receipts/2026-01-04/040404-digest/receipt.json
touch -t "$(date -v-40d +%Y%m%d%H%M 2>/dev/null || date -d '40 days ago' +%Y%m%d%H%M)" state/receipts/2026-01-04/040404-digest
check "a 40-day failure is kept longer"    "bin/rat prune | grep -q 'would remove 1'"
rm -rf state/receipts/2026-01-0*

section "isolation"
mkdir -p .claude/loops/_isolated
printf -- '---\nname: _isolated\nautonomy: assisted\nworktree: true\nrubrics: []\ntimeout: 60\n---\nchange\n' > .claude/loops/_isolated/plan.md
printf '#!/usr/bin/env bash\nprintf "changed overnight\\n" > app.txt\necho "changed app.txt"\n' > .claude/loops/_isolated/act.sh
chmod +x .claude/loops/_isolated/act.sh
bin/shift _isolated --dry-run >/dev/null 2>&1
RC=$?
ISO="$(find state/receipts -type d -name '*_isolated' | sort | tail -n 1)"
check "a worktree shift finishes"           "test $RC -le 2"
check "the repository is left alone"        "grep -q '^original$' app.txt"
check "the change arrives as a patch"       "grep -q 'changed overnight' '$ISO/diff.patch'"
check "the receipt says it was isolated"    "grep -q '\"worktree\": true' '$ISO/receipt.json'"
check "no worktree is left behind"          "test -z \"\$(ls state/worktrees 2>/dev/null)\""

check "rat apply --check reads the patch"   "bin/rat apply --check '$ISO' | grep -q 'applies cleanly'"
bin/rat apply "$ISO" >/dev/null 2>&1
check "rat apply puts it in the tree"       "grep -q 'changed overnight' app.txt"
git checkout -- app.txt 2>/dev/null
rm -rf .claude/loops/_isolated

section "bounded repair"
printf '#!/bin/sh\nexit 1\n' > check.sh
chmod +x check.sh
git add -A >/dev/null 2>&1
git -c user.email=smoke@test -c user.name=smoke commit -qm "a check that fails" >/dev/null 2>&1
mkdir -p .claude/loops/_stubborn
printf -- '---\nname: _stubborn\nautonomy: assisted\nworktree: true\nrepair: 1\nrubrics: []\ntimeout: 60\nverify: "./check.sh"\n---\nfix it\n' > .claude/loops/_stubborn/plan.md
printf '#!/usr/bin/env bash\necho "tried something"\n' > .claude/loops/_stubborn/act.sh
chmod +x .claude/loops/_stubborn/act.sh
bin/shift _stubborn --dry-run >/dev/null 2>&1
RC=$?
STUB="$(find state/receipts -type d -name '*_stubborn' | sort | tail -n 1)"
check "a failing check fails the shift"     "test $RC -eq 4"
check "it tried exactly twice"              "grep -q '\"attempts\": 2' '$STUB/receipt.json'"
check "the repair is in the trace"          "grep -q 'phase=repair' state/trace.log"
check "both verify runs were kept"          "test -f '$STUB/verify-1.log' && test -f '$STUB/verify-2.log'"

sed 's/repair: 1/repair: 5/' .claude/loops/_stubborn/plan.md > /tmp/rat-plan-5.md
cp /tmp/rat-plan-5.md .claude/loops/_stubborn/plan.md
bin/shift _stubborn --dry-run >/dev/null 2>&1
STUB="$(find state/receipts -type d -name '*_stubborn' | sort | tail -n 1)"
check "a plan cannot ask for a third try"   "grep -q '\"attempts\": 3' '$STUB/receipt.json'"
rm -rf .claude/loops/_stubborn check.sh

section "being interrupted"
mkdir -p .claude/loops/_slowpoke
printf -- '---\nname: _slowpoke\nautonomy: report-only\nrubrics: []\ntimeout: 120\n---\nsleep\n' > .claude/loops/_slowpoke/plan.md
printf '#!/usr/bin/env bash\necho "the long part"\nsleep 60\n' > .claude/loops/_slowpoke/act.sh
chmod +x .claude/loops/_slowpoke/act.sh
( bin/shift _slowpoke --dry-run >/dev/null 2>&1 & )
sleep 3
./kill.sh "smoke: the interrupt path" >/dev/null 2>&1
sleep 3
SLOW_RECEIPT="$(find state/receipts -type d -name '*_slowpoke' | sort | tail -n 1)"
check "an interrupted shift leaves a receipt" "test -f '$SLOW_RECEIPT/receipt.json'"
check "and it is marked interrupted"          "grep -q '\"verdict\": \"interrupted\"' '$SLOW_RECEIPT/receipt.json'"
check "the trace says where it was cut"       "grep -q 'status=interrupted' state/trace.log"
check "the lock was released"                 "test ! -d state/locks/_slowpoke.lock"
bin/rat resume >/dev/null 2>&1
rm -rf .claude/loops/_slowpoke

section "the validator"
check "a sound configuration passes"          "python3 bin/lib/validate.py >/dev/null"
cp .claude/loops/digest/plan.md /tmp/rat-plan.bak
python3 - <<'PY'
p = ".claude/loops/digest/plan.md"
s = open(p).read().replace("autonomy: report-only", "autonomy: report_only")
s = s.replace("rubrics: [writing, safety]", "rubrics: [writing, nonsense]")
open(p, "w").write(s)
PY
python3 bin/lib/validate.py > /tmp/rat-validate.out 2>&1
RC=$?
check "a bad autonomy level is caught"        "test $RC -eq 1 && grep -q 'report_only' /tmp/rat-validate.out"
check "a missing rubric is caught"            "grep -q 'nonsense' /tmp/rat-validate.out"
cp /tmp/rat-plan.bak .claude/loops/digest/plan.md
check "and it passes again once fixed"        "python3 bin/lib/validate.py >/dev/null"

section "replaying a shift"
bin/shift digest --dry-run >/dev/null 2>&1
ORIGINAL="$(find state/receipts -type d -name '*-digest' | sort | tail -n 1)"
bin/rat replay "$ORIGINAL" --dry-run > /tmp/rat-replay.out 2>&1
RC=$?
check "replay runs from the saved prompt"     "test $RC -eq 0"
check "it compares the two answers"           "grep -q 'similarity' /tmp/rat-replay.out"
REPLAY="$(find state/receipts -type d -name '*-replay' | sort | tail -n 1)"
check "the replay names its original"         "grep -q 'replay_of' '$REPLAY/receipt.json'"
check "the original was not overwritten"      "test -f '$ORIGINAL/receipt.json'"

section "policy per path"
mkdir -p .claude/loops/_docs_writer .claude/loops/_brain_surgeon docs
printf 'a doc\n' > docs/page.md
git add -A >/dev/null 2>&1
git -c user.email=smoke@test -c user.name=smoke commit -qm "a doc" >/dev/null 2>&1
printf -- '---\nname: _docs_writer\nautonomy: assisted\nrubrics: []\ntimeout: 30\n---\nwrite\n' > .claude/loops/_docs_writer/plan.md
printf '#!/usr/bin/env bash\nprintf "edited\\n" > docs/page.md\necho done\n' > .claude/loops/_docs_writer/act.sh
printf -- '---\nname: _brain_surgeon\nautonomy: assisted\nrubrics: []\ntimeout: 30\n---\nwrite\n' > .claude/loops/_brain_surgeon/plan.md
printf '#!/usr/bin/env bash\nprintf "# hijacked\\n" >> bin/rat\necho done\n' > .claude/loops/_brain_surgeon/act.sh
chmod +x .claude/loops/_docs_writer/act.sh .claude/loops/_brain_surgeon/act.sh

bin/shift _docs_writer --dry-run >/dev/null 2>&1
RC=$?
check "docs are within an assisted loop"   "test $RC -le 2"
git checkout -- docs/page.md 2>/dev/null

bin/shift _brain_surgeon --dry-run >/dev/null 2>&1
RC=$?
SURGERY="$(find state/receipts -type d -name '*_brain_surgeon' | sort | tail -n 1)"
check "the harness itself is out of reach"  "test $RC -eq 3"
check "and the rule that stopped it is named" "grep -q 'path-policy' '$SURGERY/guard.json'"
git checkout -- bin/rat 2>/dev/null
rm -rf .claude/loops/_docs_writer .claude/loops/_brain_surgeon

section "packs"
check "packs can be listed"                "bin/rat add --list | grep -q todo-harvest"
check "a pack installs"                    "bin/rat add todo-harvest >/dev/null && test -x .claude/loops/todo-harvest/act.sh"
check "installing twice is refused"        "! bin/rat add todo-harvest >/dev/null 2>&1"
bin/shift todo-harvest --dry-run >/dev/null 2>&1
RC=$?
check "an installed pack runs"             "test $RC -le 2"
check "and nothing scheduled it"           "! grep -q todo-harvest .claude/loops/schedule.yml"
rm -rf .claude/loops/todo-harvest

section "the record can be checked"
check "the trace lines are chained"       "grep -q ' h=[0-9a-f]' state/trace.log"
check "audit says the chain holds"        "python3 bin/lib/audit.py state | grep -q 'the chain holds'"
cp state/trace.log /tmp/rat-trace.ok
python3 - <<'PY'
lines = open("state/trace.log").read().splitlines()
lines[1] = lines[1].replace("status=ok", "status=perfect")
open("state/trace.log", "w").write("\n".join(lines) + "\n")
PY
python3 bin/lib/audit.py state > /tmp/rat-audit.out 2>&1
RC=$?
check "an edited trace line is caught"    "test $RC -eq 1 && grep -q 'chain breaks at line 2' /tmp/rat-audit.out"
cp /tmp/rat-trace.ok state/trace.log
check "and it passes again once restored" "python3 bin/lib/audit.py state >/dev/null"

EDITED="$(sed -n 's/.*dir=\([^ ]*\).*rhash=.*/\1/p' state/trace.log | tail -n 1)/receipt.json"
cp "$EDITED" /tmp/rat-receipt.ok
python3 - "$EDITED" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["verdict"] = "pass"
json.dump(data, open(path, "w"), indent=2)
PY
python3 bin/lib/audit.py state > /tmp/rat-audit2.out 2>&1
RC=$?
check "an edited receipt is caught"       "test $RC -eq 1 && grep -q 'no longer match' /tmp/rat-audit2.out"
cp /tmp/rat-receipt.ok "$EDITED"
check "audit speaks json"                 "python3 bin/lib/audit.py state --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d[\"chain_ok\"]'"

section "the front door"
check "rat list prints the schedule"      "bin/rat list | grep -q pr-hunter"
check "rat status prints today's spend"   "bin/rat status | grep -q today"
check "rat receipts prints a row"         "bin/rat receipts 50 | grep -q digest"
check "rat show opens the last receipt"   "bin/rat show | grep -q verdict"
check "rat trace tails the log"           "bin/rat trace 5 | grep -q phase="
check "rat new scaffolds a loop"          "bin/rat new probe && test -x .claude/loops/probe/act.sh"
check "a scaffolded loop runs"             "bin/shift probe --dry-run; test \$? -le 2"
check "rat prune runs with nothing to do"  "bin/rat prune | grep -q 'nothing to prune\|would remove 0'"
check "receipts filter by loop"           "bin/rat receipts --loop digest 20 | grep -q digest"
check "receipts filter out what is absent" "bin/rat receipts --loop nosuchloop 20 | grep -q 'nothing matches'"
check "receipts speak json"               "bin/rat receipts 3 --json | python3 -c 'import json,sys; json.load(sys.stdin)'"
check "status speaks json"                "bin/rat status --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert \"loops\" in d'"
check "rat doctor reports"                "bin/rat doctor >/dev/null 2>&1; test \$? -le 1"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
