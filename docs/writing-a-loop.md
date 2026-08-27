# Writing a loop

A loop is two files and a line in the schedule.

```bash
bin/rat new release-notes
```

That gives you `.claude/loops/release-notes/plan.md` and `act.sh`, copied from
the template. Nothing runs until you add the loop to `schedule.yml`, and you can
run it by hand as often as you like before you do.

## Start from the sentence

Before either file, write the sentence out loud: **"every N, look at X, and if Y,
do Z, then stop when W."** If you cannot finish it, you do not have a loop yet -
you have a task, and a task is better done in a chat window where you are
watching.

The two halves that matter are the trigger and the ending. Most loops that go
wrong went wrong at the ending.

## plan.md

Front matter is the machine-readable part:

```yaml
---
name: release-notes
autonomy: report-only        # report-only | assisted | autonomous
rubrics: [writing, safety]   # which graders see the output
timeout: 300                 # seconds, hard
max_usd: 0.25                # this shift's ceiling
verify: ""                   # a shell command that must exit 0
---
```

`timeout` and `max_usd` override `settings.json` for this loop only. `verify` is
the deterministic half of "did it work" - a test command, a linter, a script that
greps for the thing that should now be true. Leave it empty for report-only
loops; there is nothing to verify when nothing changed.

The body is the prompt, and it is read as instructions to a colleague who has
never seen this repository:

- **what you are given** - what `act.sh` collected. Do not make the model go
  looking for facts a script already gathered.
- **what to produce** - the shape of the output. "A report" is not a shape. Show
  the block, the table, or the four sentences you want back.
- **stop conditions** - at least two, and every one checkable.
- **cursor** - what to write to `$RAT_RECEIPT/cursor.json` if this loop should
  remember anything between shifts.

Write stop conditions as things that are true, not as an amount of effort:

```
good:  every open PR has a block. stop.
good:  two attempts produced the same result. stop and report both.
bad:   do your best, then wrap up.
```

## act.sh

The script is the shift. Environment it gets:

| variable | what it is |
|---|---|
| `RAT_ROOT` | repository root |
| `RAT_LOOP` | this loop's name |
| `RAT_RECEIPT` | this shift's receipt folder - write anything you want kept |
| `RAT_TIMEOUT` | seconds this shift has left |
| `rat-agent` | on PATH: pipe a prompt in, get the model's answer out |

stdout becomes `output.md`. stderr becomes `stderr.log`. Exit non-zero and the
shift is recorded as an error, which is the correct outcome when the model could
not be reached - an empty file that claims success is worse than a failure.

The shape that works:

```bash
{
  echo "### open pull requests"
  gh pr list --state open --limit 25 --json number,title,createdAt
} > "$RAT_RECEIPT/facts.md"

{
  cat "$RAT_RECEIPT/prompt.md"     # contract + rubrics + cursor + your plan
  echo
  cat "$RAT_RECEIPT/facts.md"
} | rat-agent --tag act
```

Gather, then ask. Three rules that keep loops cheap and reviewable:

1. **Anything a script can determine never costs a token.** Dates, file lists,
   test output, PR metadata, git history.
2. **One model call per shift where possible.** If you need two, tag them
   (`--tag act`, `--tag act2`) so the receipt shows what each cost.
3. **Write the facts to the receipt.** When tomorrow's verdict looks wrong, you
   want to see what the shift actually knew, not guess at it.

## Test it before you schedule it

```bash
bin/shift release-notes --prompt-only    # read the brief the model will get
bin/shift release-notes --dry-run        # every phase for real, model stubbed
bin/shift release-notes                  # for real, once, while you watch
```

Read the receipt after each. The first two cost nothing.

## Then schedule it

```yaml
  - name: release-notes
    every: 1d
    at: "06:30"
    days: mon-fri
    enabled: true
```

Match the interval to how fast the underlying thing changes, not to how eager you
are. A loop that fires every fifteen minutes over a repository that changes twice
a day spends most of its shifts writing "nothing to do" - and you will start
skipping the receipts, which is how a loop stops being useful.

No crontab change is needed - the single `run-due` tick already installed reads
this file every time it fires. Regenerate it only if you added a loop that ticks
faster than anything you had before:

```bash
(crontab -l 2>/dev/null | grep -v 'bin/rat run-due'; bin/rat cron) | crontab -
```

## Week one is report-only

Give a new loop no write access for its first week. `autonomy: report-only`,
empty `verify`, an `act.sh` that only reads. You will learn more from seven
receipts describing what it *would* have done than from one merged PR.

Promote it when you have read a week of receipts and disagreed with none of them.
