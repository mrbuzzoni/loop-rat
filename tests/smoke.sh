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
cp "$SRC/install.sh" "$SRC/contract.local.example.md" "$LAB/"
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

section "found while auditing"
# four shifts at once must not break the chain: trace writes are serialized
rm -f state/trace.log
( bin/shift digest --dry-run >/dev/null 2>&1 & bin/shift pr-hunter --dry-run >/dev/null 2>&1 &
  bin/shift docs-drift --dry-run >/dev/null 2>&1 & bin/shift cost-watch --dry-run >/dev/null 2>&1 & wait )
check "concurrent shifts keep the chain"    "python3 bin/lib/audit.py state | grep -q 'the chain holds'"

# an agent configured with no arguments is a normal agent
mkdir -p state/scratch
cat > fake-agent <<'EOF'
#!/usr/bin/env python3
import json, sys
sys.stdin.read()
print(json.dumps({"result": "a fake answer", "total_cost_usd": 0.0123}))
EOF
chmod +x fake-agent
cp .claude/loops/settings.json /tmp/rat-settings-real.json
python3 - <<'PY'
import json
p = ".claude/loops/settings.json"
s = json.load(open(p))
s["agent"] = {"command": "./fake-agent", "args": [], "result_field": "result",
              "cost_field": "total_cost_usd"}
json.dump(s, open(p, "w"), indent=2)
PY
RAT_RECEIPT="$PWD/state/scratch" RAT_LOOP=argless bin/rat-agent --tag probe > /tmp/rat-argless.out 2>&1 <<< "hi"
RC=$?
check "an agent with no args is fine"       "test $RC -eq 0 && grep -q 'a fake answer' /tmp/rat-argless.out"
check "and its price is recorded"           "grep -q '0.0123' state/scratch/agent-probe.cost"
cp /tmp/rat-settings-real.json .claude/loops/settings.json
rm -rf state/scratch fake-agent

# a transient failure is waited out; a permanent one is reported at once
mkdir -p state/scratch
cat > flaky-agent <<'EOF'
#!/usr/bin/env python3
import json, os, sys
sys.stdin.read()
counter = "flaky-count"
tries = int(open(counter).read()) if os.path.exists(counter) else 0
open(counter, "w").write(str(tries + 1))
if tries < 2:
    print(json.dumps({"is_error": True, "result": "API Error: 529 Overloaded.",
                      "total_cost_usd": 0.003}))
else:
    print(json.dumps({"result": "the answer, on the third try",
                      "total_cost_usd": 0.05}))
EOF
cat > broken-agent <<'EOF'
#!/usr/bin/env python3
import json, sys
sys.stdin.read()
print(json.dumps({"is_error": True, "result": "Invalid model name: nonsense",
                  "total_cost_usd": 0.0}))
EOF
chmod +x flaky-agent broken-agent
cp .claude/loops/settings.json /tmp/rat-settings-real2.json
python3 - <<'PY'
import json
p = ".claude/loops/settings.json"
s = json.load(open(p))
s["agent"] = {"command": "./flaky-agent", "args": [], "result_field": "result",
              "cost_field": "total_cost_usd", "retries": 2,
              "retry_delay_seconds": 1}
json.dump(s, open(p, "w"), indent=2)
PY
rm -f flaky-count
RAT_RECEIPT="$PWD/state/scratch" RAT_LOOP=retry-probe bin/rat-agent --tag act   > /tmp/rat-retry.out 2>/dev/null <<< "hi"
RC=$?
check "a transient failure is retried"      "test $RC -eq 0 && grep -q 'third try' /tmp/rat-retry.out"
check "the report holds only the answer"    "! grep -q 'could not reach' /tmp/rat-retry.out"
check "every attempt is billed"             "python3 -c \"
import json
by = json.load(open('state/budget.json'))['by_loop']['retry-probe']
assert abs(by - 0.056) < 0.001, by
\""
check "the retries are in the trace"        "grep -q 'status=retrying' state/trace.log"

python3 - <<'PY'
import json
p = ".claude/loops/settings.json"
s = json.load(open(p))
s["agent"]["command"] = "./broken-agent"
json.dump(s, open(p, "w"), indent=2)
PY
START=$(date +%s)
RAT_RECEIPT="$PWD/state/scratch" RAT_LOOP=broken-probe bin/rat-agent --tag act2   > /tmp/rat-broken.out 2>/dev/null <<< "hi"
RC=$?
ELAPSED=$(( $(date +%s) - START ))
check "a permanent failure is not retried"  "test $RC -eq 1 && test $ELAPSED -lt 3"
check "and the receipt says what it was"    "grep -q 'Invalid model name' /tmp/rat-broken.out"
cp /tmp/rat-settings-real2.json .claude/loops/settings.json
rm -rf state/scratch flaky-agent broken-agent flaky-count

# an agent that produces nothing is a failure with a sentence, not a traceback
mkdir -p state/scratch
python3 bin/lib/agent_result.py state/scratch/none.json state/scratch/none.cost result total_cost_usd > /tmp/rat-none.out 2>/dev/null
RC=$?
check "a missing response fails cleanly"    "test $RC -eq 2 && grep -q 'could not reach' /tmp/rat-none.out"
rm -rf state/scratch

# the grader's answer has to survive the trip from JSON to grade.json
mkdir -p .claude/loops/_graded
printf -- '---\nname: _graded\nautonomy: report-only\nrubrics: [safety]\ntimeout: 60\n---\nreport\n' > .claude/loops/_graded/plan.md
printf '#!/usr/bin/env bash\necho "a clean night"\n' > .claude/loops/_graded/act.sh
chmod +x .claude/loops/_graded/act.sh
cat > grading-agent <<'EOF'
#!/usr/bin/env python3
import json, sys
prompt = sys.stdin.read()
if "grader" in prompt:
    answer = ('Here is my assessment.\n\n'
              '{"verdict": "pass", "score": 88, "notes": "the report matches what '
              'the shift did", "fix_first": ""}')
else:
    answer = "**What I found** - nothing to report."
print(json.dumps({"result": answer, "total_cost_usd": 0.02}))
EOF
chmod +x grading-agent
cp .claude/loops/settings.json /tmp/rat-settings-real3.json
python3 - <<'PY'
import json
p = ".claude/loops/settings.json"
s = json.load(open(p))
s["agent"] = {"command": "./grading-agent", "args": [], "result_field": "result",
              "cost_field": "total_cost_usd", "retries": 0}
json.dump(s, open(p, "w"), indent=2)
PY
bin/shift _graded >/dev/null 2>&1
RC=$?
GRADED="$(find state/receipts -type d -name '*_graded' | sort | tail -n 1)"
check "a real verdict reaches the receipt"   "test $RC -eq 0 && grep -q '\"verdict\": \"pass\"' '$GRADED/grade.json'"
check "and so does the score"                "grep -q '\"score\": 88' '$GRADED/grade.json'"
check "prose around the json is tolerated"   "grep -q 'matches what' '$GRADED/grade.json'"
check "the shift passed on that verdict"     "grep -q '\"verdict\": \"pass\"' '$GRADED/receipt.json'"
cp /tmp/rat-settings-real3.json .claude/loops/settings.json
rm -rf .claude/loops/_graded grading-agent

# an in-place shift must not touch the index you were using, and its patch
# must contain only what it changed
printf 'my staged work\n' > app.txt
git add app.txt
mkdir -p .claude/loops/_inplace
printf -- '---\nname: _inplace\nautonomy: assisted\nrubrics: []\ntimeout: 30\n---\nchange\n' > .claude/loops/_inplace/plan.md
printf '#!/usr/bin/env bash\nprintf "by the loop\\n" > loop-made.txt\necho done\n' > .claude/loops/_inplace/act.sh
chmod +x .claude/loops/_inplace/act.sh
bin/shift _inplace --dry-run >/dev/null 2>&1
INPLACE="$(find state/receipts -type d -name '*_inplace' | sort | tail -n 1)"
check "staged work stays staged"            "git diff --cached --name-only | grep -q '^app.txt$'"
check "the patch holds only the loop's file" "grep -q 'loop-made.txt' '$INPLACE/diff.patch' && ! grep -q 'app.txt' '$INPLACE/diff.patch'"
git reset -q app.txt; git checkout -- app.txt 2>/dev/null; rm -f loop-made.txt
rm -rf .claude/loops/_inplace

section "the demos are honest"
check "the readme's check count is true"   "python3 -c \"
import re
readme = open('$SRC/README.md').read()
claimed = int(re.search(r'(\\d+) checks against a scratch copy', readme).group(1))
suite = open('$SRC/tests/smoke.sh').read()
run = len(re.findall(r'^check \\\"', suite, re.M))
assert abs(claimed - run) <= 2, 'readme says %d, the suite runs %d' % (claimed, run)
\""
check "every gif the readme shows exists"  "python3 -c \"
import re, os, sys
readme = open('$SRC/README.md').read() if os.path.exists('$SRC/README.md') else ''
missing = [m for m in re.findall(r'docs/assets/(\S+?\.gif)', readme)
           if not os.path.exists(os.path.join('$SRC', 'docs/assets', m))]
assert not missing, missing
\""
check "and no absolute path is baked in"   "! grep -rl 'Users/' '$SRC/docs/assets' 2>/dev/null | grep -q ."

section "awkward input"
bin/shift "bad name" --dry-run >/dev/null 2>&1
RC=$?
check "a name with a space is refused"     "test $RC -eq 2"
bin/shift "../escape" --dry-run >/dev/null 2>&1
RC=$?
check "a name that climbs out is refused"  "test $RC -eq 2"

mkdir -p .claude/loops/_broken
printf -- '---\nname: _broken\ntimeout: not-a-number\nrepair: lots\nrubrics: []\n---\nx\n' > .claude/loops/_broken/plan.md
printf '#!/usr/bin/env bash\necho hi\n' > .claude/loops/_broken/act.sh
chmod +x .claude/loops/_broken/act.sh
bin/shift _broken --dry-run > /tmp/rat-broken-plan.out 2>&1
RC=$?
check "a plan with a bad number still runs" "test $RC -le 2"
check "and says which value it ignored"     "grep -q 'not a number' /tmp/rat-broken-plan.out"
rm -rf .claude/loops/_broken

cp .claude/loops/settings.json /tmp/rat-settings-real7.json
printf '{"caps": ' > .claude/loops/settings.json
bin/shift digest --dry-run > /tmp/rat-nosettings.out 2>&1
RC=$?
check "no readable settings, no shift"      "test $RC -eq 1"
check "because that means no brakes"        "grep -q 'no caps and no denylist' /tmp/rat-nosettings.out"
cp /tmp/rat-settings-real7.json .claude/loops/settings.json

section "wherever this is running"
check "python 3 is found by some name"     "bash -c '. bin/lib/common.sh; rat_python >/dev/null && rat_py -c \"import sys; raise SystemExit(0 if sys.version_info[0]==3 else 1)\"'"
check "the platform is named"              "bash -c '. bin/lib/common.sh; rat_os' | grep -qE 'macos|linux|windows|unknown'"
check "a process tree can be killed"       "bash -c '
. bin/lib/common.sh
bash -c \"sleep 25 & sleep 25; wait\" &
PARENT=\$!
sleep 1
rat_kill_tree \"\$PARENT\" KILL
sleep 1
! kill -0 \"\$PARENT\" 2>/dev/null'"
check "cron output exists for unix"        "python3 bin/lib/schedule.py cron .claude/loops/schedule.yml \"\$PWD\" --cron | grep -q 'run-due'"
check "and for windows"                    "python3 bin/lib/schedule.py cron .claude/loops/schedule.yml \"\$PWD\" --windows | grep -q schtasks"
check "the windows wrapper avoids quoting" "python3 bin/lib/schedule.py cron .claude/loops/schedule.yml \"\$PWD\" --windows | grep -q 'loop-rat.cmd'"
check "no bare seq anywhere in the harness" "! grep -rn '\\bseq \\+[0-9]' bin packs .claude/loops 2>/dev/null | grep -v Binary"

section "a loop that keeps failing"
mkdir -p .claude/loops/_doomed
printf -- '---\nname: _doomed\nautonomy: report-only\nrubrics: []\ntimeout: 30\nverify: "false"\n---\nfail\n' > .claude/loops/_doomed/plan.md
printf '#!/usr/bin/env bash\necho trying\n' > .claude/loops/_doomed/act.sh
chmod +x .claude/loops/_doomed/act.sh
bin/shift _doomed --dry-run >/dev/null 2>&1
bin/shift _doomed --dry-run >/dev/null 2>&1
bin/shift _doomed --dry-run >/dev/null 2>&1
check "failures are counted"               "test \"\$(python3 bin/lib/conf.py get state/checkpoint.json loops._doomed.consecutive_failures)\" = 3"
bin/shift _doomed --dry-run >/dev/null 2>&1
RC=$?
check "the fourth night is refused"        "test $RC -eq 75"
check "and the trace says why"             "grep -q 'reason=breaker' state/trace.log"
bin/rat resume _doomed >/dev/null 2>&1
check "resume clears one loop"             "test \"\$(python3 bin/lib/conf.py get state/checkpoint.json loops._doomed.consecutive_failures)\" = 0"
bin/shift _doomed --dry-run >/dev/null 2>&1
RC=$?
check "and it runs again after that"       "test $RC -ne 75"
rm -rf .claude/loops/_doomed

section "telling you about it"
cp .claude/loops/settings.json /tmp/rat-settings-real6.json
python3 - <<'PY'
import json
p = ".claude/loops/settings.json"
s = json.load(open(p))
s["notify"] = {"command": 'printf "%s|%s\n" "$RAT_VERDICT" "$RAT_NOTIFY_LOOP" >> notified.txt',
               "on": "needs-review fail blocked interrupted"}
json.dump(s, open(p, "w"), indent=2)
PY
rm -f notified.txt
bin/shift digest --dry-run >/dev/null 2>&1
check "a shift worth reading notifies"     "grep -q 'needs-review|digest' notified.txt"
python3 - <<'PY'
import json
p = ".claude/loops/settings.json"
s = json.load(open(p))
s["notify"]["on"] = "fail"
json.dump(s, open(p, "w"), indent=2)
PY
rm -f notified.txt
bin/shift digest --dry-run >/dev/null 2>&1
check "and a quiet one stays quiet"        "test ! -f notified.txt"
cp /tmp/rat-settings-real6.json .claude/loops/settings.json
rm -f notified.txt

section "paying for it"
mkdir -p state/scratch
cat > echo-agent <<'EOF'
#!/usr/bin/env python3
import json, sys
sys.stdin.read()
print(json.dumps({"result": "args: " + " ".join(sys.argv[1:]), "total_cost_usd": 0.01}))
EOF
chmod +x echo-agent
cp .claude/loops/settings.json /tmp/rat-settings-real5.json
python3 - <<'PY'
import json
p = ".claude/loops/settings.json"
s = json.load(open(p))
s["agent"] = {"command": "./echo-agent", "args": ["-p"], "result_field": "result",
              "cost_field": "total_cost_usd", "retries": 0, "model_flag": "--model"}
json.dump(s, open(p, "w"), indent=2)
PY
RAT_RECEIPT="$PWD/state/scratch" RAT_LOOP=m bin/rat-agent --tag plain > /tmp/rat-model1.out 2>/dev/null <<< "hi"
RAT_MODEL=haiku RAT_RECEIPT="$PWD/state/scratch" RAT_LOOP=m bin/rat-agent --tag cheap > /tmp/rat-model2.out 2>/dev/null <<< "hi"
check "a loop can pick a cheaper model"     "grep -q -- '--model haiku' /tmp/rat-model2.out"
check "and the default is left alone"       "! grep -q -- '--model' /tmp/rat-model1.out"
check "calls are counted, not only dollars" "python3 -c \"
import json
b = json.load(open('state/budget.json'))
assert sum(b['calls'].values()) >= 2, b
\""
rm -rf state/scratch

python3 - <<'PY'
import json
p = ".claude/loops/settings.json"
s = json.load(open(p))
s["caps"]["max_calls_per_day"] = 1
json.dump(s, open(p, "w"), indent=2)
PY
bin/shift digest >/dev/null 2>&1
bin/shift digest >/dev/null 2>&1
RC=$?
check "a used-up day starts no shift"       "test $RC -eq 75"
check "and says so in the trace"            "grep -q 'reason=calls' state/trace.log"
cp /tmp/rat-settings-real5.json .claude/loops/settings.json
rm -f echo-agent

section "setting up a strange repository"
NEWREPO="$(mktemp -d)"
( cd "$NEWREPO" && git init -q . \
  && printf '{"name":"app","scripts":{"build":"true","test":"true"}}\n' > package.json \
  && git add -A && git -c user.email=s@t -c user.name=s commit -qm x ) >/dev/null 2>&1
./install.sh "$NEWREPO" > /tmp/rat-install.out 2>&1
check "the installer leaves nothing scheduled" "grep -q 'loops: \[\]' '$NEWREPO/.claude/loops/schedule.yml'"
check "and does not carry this repo's loops"   "test ! -d '$NEWREPO/.claude/loops/docs-drift'"
( cd "$NEWREPO" && bin/rat init > /tmp/rat-init.out 2>&1 )
check "init recognises a node project"         "grep -q 'node project' /tmp/rat-init.out"
check "it installs loops that fit"             "test -d '$NEWREPO/.claude/loops/build-doctor' && test -d '$NEWREPO/.claude/loops/secret-sweep'"
check "it writes a schedule"                   "grep -q 'name: digest' '$NEWREPO/.claude/loops/schedule.yml'"
check "the code-changing loop starts off"      "python3 -c \"
import sys
text = open('$NEWREPO/.claude/loops/schedule.yml').read()
block = text.split('name: test-mender')[1] if 'test-mender' in text else ''
assert 'enabled: false' in block, block
\""
check "the caps are set for a subscription"    "python3 -c \"
import json
caps = json.load(open('$NEWREPO/.claude/loops/settings.json'))['caps']
assert caps['max_calls_per_day'] == 12, caps
\""
( cd "$NEWREPO" && bin/rat doctor > /tmp/rat-newdoctor.out 2>&1 )
check "and the result passes its own doctor"   "grep -q 'nothing blocking' /tmp/rat-newdoctor.out"
( cd "$NEWREPO" && bin/shift secret-sweep --dry-run >/dev/null 2>&1 )
RC=$?
check "a fresh install can run a shift"        "test $RC -le 2"
rm -rf "$NEWREPO"

section "loops that build things"
mkdir -p .claude/loops/_installer
printf -- '---\nname: _installer\nautonomy: report-only\nworktree: true\nrubrics: []\ntimeout: 60\n---\ninstall\n' > .claude/loops/_installer/plan.md
printf '#!/usr/bin/env bash\nmkdir -p node_modules/pkg\nprintf "x\\n" > node_modules/pkg/index.js\nprintf "{}\\n" > package-lock.json\necho "installed"\n' > .claude/loops/_installer/act.sh
chmod +x .claude/loops/_installer/act.sh
bin/shift _installer --dry-run >/dev/null 2>&1
RC=$?
INST="$(find state/receipts -type d -name '*_installer' | sort | tail -n 1)"
check "a discarded checkout is not a violation" "test $RC -le 2"
check "but what happened there is recorded"     "grep -q 'observed\|note' '$INST/guard.json'"
rm -rf .claude/loops/_installer

mkdir -p .claude/loops/_lockfile
printf -- '---\nname: _lockfile\nautonomy: assisted\nworktree: true\nrubrics: []\ntimeout: 60\n---\nwrite\n' > .claude/loops/_lockfile/plan.md
printf '#!/usr/bin/env bash\nprintf "{}\\n" > package-lock.json\necho done\n' > .claude/loops/_lockfile/act.sh
chmod +x .claude/loops/_lockfile/act.sh
bin/shift _lockfile --dry-run >/dev/null 2>&1
RC=$?
check "a patch meant for you is still guarded" "test $RC -eq 3"
rm -rf .claude/loops/_lockfile

section "rubric packs"
printf 'diff --git a/src/app.py b/src/app.py\n+++ b/src/app.py\n' > /tmp/rat-py.patch
printf 'diff --git a/bin/x.sh b/bin/x.sh\n+++ b/bin/x.sh\n' > /tmp/rat-sh.patch
check "a python diff pulls the python pack"  "python3 bin/lib/rubrics.py .claude/loops/rubrics /tmp/rat-py.patch code | grep -q packs/python"
check "and not the shell one"                "! python3 bin/lib/rubrics.py .claude/loops/rubrics /tmp/rat-py.patch code | grep -q packs/shell"
check "a shell diff pulls the shell pack"    "python3 bin/lib/rubrics.py .claude/loops/rubrics /tmp/rat-sh.patch code | grep -q packs/shell"
check "prose loops get no packs at all"      "! python3 bin/lib/rubrics.py .claude/loops/rubrics /tmp/rat-py.patch writing | grep -q packs/"

section "two graders"
mkdir -p .claude/loops/_argued
printf -- '---\nname: _argued\nautonomy: report-only\nrubrics: [safety]\ntimeout: 60\n---\nreport\n' > .claude/loops/_argued/plan.md
printf '#!/usr/bin/env bash\necho "a night worth arguing about"\n' > .claude/loops/_argued/act.sh
chmod +x .claude/loops/_argued/act.sh
cat > split-agent <<'EOF'
#!/usr/bin/env python3
import json, os, sys
prompt = sys.stdin.read()
if "grader" in prompt:
    counter = "grader-count"
    seen = int(open(counter).read()) if os.path.exists(counter) else 0
    open(counter, "w").write(str(seen + 1))
    answer = ('{"verdict":"pass","score":91,"notes":"it matches"}' if seen == 0
              else '{"verdict":"fail","score":40,"notes":"it does not match"}')
else:
    answer = "**What I found** - a night worth arguing about."
print(json.dumps({"result": answer, "total_cost_usd": 0.01}))
EOF
chmod +x split-agent
cp .claude/loops/settings.json /tmp/rat-settings-real4.json
python3 - <<'PY'
import json
p = ".claude/loops/settings.json"
s = json.load(open(p))
s["agent"] = {"command": "./split-agent", "args": [], "result_field": "result",
              "cost_field": "total_cost_usd", "retries": 0}
s["grading"] = {"mode": "auto", "graders": 2}
json.dump(s, open(p, "w"), indent=2)
PY
rm -f grader-count
bin/shift _argued >/dev/null 2>&1
ARGUED="$(find state/receipts -type d -name '*_argued' | sort | tail -n 1)"
check "both readings are kept"               "python3 -c \"
import json
g = json.load(open('$ARGUED/grade.json'))
assert g['graders'] == 2, g
assert len(g['each']) == 2, g
\""
check "disagreement is recorded as such"     "grep -q '\"agreement\": false' '$ARGUED/grade.json'"
check "the harsher verdict wins"             "grep -q '\"verdict\": \"fail\"' '$ARGUED/grade.json'"
check "the trace says they disagreed"        "grep -q 'status=disagreed' state/trace.log"
check "and it becomes a queue"               "bin/rat receipts --disagreed 20 | grep -q _argued"
check "the audit calls it out"               "bin/rat audit --days 1 | grep -q 'graders disagreed'"

rm -f grader-count
cat > agreeing-agent <<'EOF'
#!/usr/bin/env python3
import json, sys
prompt = sys.stdin.read()
answer = ('{"verdict":"pass","score":90,"notes":"it holds"}' if "grader" in prompt
          else "**What I found** - a quiet night.")
print(json.dumps({"result": answer, "total_cost_usd": 0.01}))
EOF
chmod +x agreeing-agent
python3 - <<'PY'
import json
p = ".claude/loops/settings.json"
s = json.load(open(p))
s["agent"]["command"] = "./agreeing-agent"
json.dump(s, open(p, "w"), indent=2)
PY
bin/shift _argued >/dev/null 2>&1
RC=$?
AGREED="$(find state/receipts -type d -name '*_argued' | sort | tail -n 1)"
check "agreement passes the shift"           "test $RC -eq 0 && grep -q '\"agreement\": true' '$AGREED/grade.json'"

section "calibrating a rubric"
bin/rat calibrate --days 1 --limit 3 > /tmp/rat-calibrate.out 2>&1
check "calibrate re-reads old receipts"      "grep -qE '[0-9]+ receipt\(s\) re-read' /tmp/rat-calibrate.out"
check "it leaves the originals alone"        "grep -q 'originals are untouched' /tmp/rat-calibrate.out"
check "and keeps its own working copy"       "test -d state/calibrations"
cp /tmp/rat-settings-real4.json .claude/loops/settings.json
rm -rf .claude/loops/_argued split-agent agreeing-agent grader-count

section "memory that travels"
REMOTE="$(mktemp -d)"
git init -q --bare "$REMOTE/origin.git"
git remote add origin "$REMOTE/origin.git" 2>/dev/null || git remote set-url origin "$REMOTE/origin.git"
git add -A >/dev/null 2>&1
git -c user.email=smoke@test -c user.name=smoke commit -qm "before pushing state" >/dev/null 2>&1
git -c user.email=smoke@test -c user.name=smoke push -q origin HEAD:main 2>/dev/null
git config user.email smoke@test
git config user.name smoke
bin/rat state push > /tmp/rat-state.out 2>&1
check "the memory is pushed to a branch"     "grep -q 'pushed' /tmp/rat-state.out"
SECOND="$(mktemp -d)"
git clone -q "$REMOTE/origin.git" "$SECOND/repo" 2>/dev/null
cp -R bin .claude CONTRACT.md kill.sh "$SECOND/repo/" 2>/dev/null
mkdir -p "$SECOND/repo/state"
( cd "$SECOND/repo" && bin/rat state pull > /tmp/rat-state-pull.out 2>&1 )
check "a fresh checkout can take it back"    "grep -q 'pulled' /tmp/rat-state-pull.out"
check "and it knows what already ran"        "test -f '$SECOND/repo/state/checkpoint.json'"
check "the chain survives the trip"          "( cd '$SECOND/repo' && python3 bin/lib/audit.py state | grep -q 'chain holds' )"
rm -rf "$REMOTE" "$SECOND"
git remote remove origin 2>/dev/null || true

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
# The suite has spent a day's worth of calls on fake agents by now, and the cap
# is doing its job. Reset the ledger so the checks below test what they mean to.
rm -f state/budget.json
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
