# Loop Rat

[![tests](https://github.com/mrbuzzoni/loop-rat/actions/workflows/test.yml/badge.svg)](https://github.com/mrbuzzoni/loop-rat/actions/workflows/test.yml)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

An autonomous loop agent. It is a folder you drop into a repository: it wakes
your coding agent on a schedule, keeps it inside rules you wrote down, grades
what it did with a second agent, and leaves a dated receipt you read in the
morning.

Not a framework, not a wrapper around the model. A dozen files of bash and
python - plus one `act.sh` per loop - that answer the four questions any
unattended agent has to answer before you can go to sleep:

- **what starts a run** - `schedule.yml`
- **what it may do** - `CONTRACT.md`, and the denylist in `settings.json`
- **what ends a run** - a stop condition in the plan, a timeout, a spend cap
- **what it left behind** - a receipt folder, a trace log, a checkpoint

Everything runs locally. No service, no database, nothing to sign up for.

---

## The anatomy

```
your-project/
│
├── CONTRACT.md               the shift rules, committed
├── contract.local.md         your personal overrides, gitignored
│
├── .claude/
│   └── loops/
│       ├── settings.json     spend caps, timeouts, the denylist
│       ├── schedule.yml      when each loop fires
│       ├── rubrics/
│       │   ├── code.md       what "done" means for a diff
│       │   ├── writing.md    what "done" means for prose
│       │   └── safety.md     what must never happen
│       ├── pr-hunter/
│       │   ├── plan.md       wake, read, act, verify
│       │   └── act.sh        the actual work
│       ├── test-mender/
│       └── digest/
│
├── state/                    survives every crash, gitignored
│   ├── receipts/2026-09-02/  one folder per shift
│   ├── trace.log             what actually happened, one line per phase
│   ├── checkpoint.json       where to resume
│   └── budget.json           what today has cost so far
│
├── bin/
│   ├── rat                   the front door
│   ├── shift                 runs one shift, end to end
│   └── rat-agent             the only place that talks to a model
│
├── kill.sh                   the panic file
└── .mcp.json                 the tools a shift may touch
```

One run of one loop is a **shift**. The rat works nights; you read receipts over
coffee.

---

## Start

```bash
git clone https://github.com/mrbuzzoni/loop-rat.git
cd loop-rat
bin/rat doctor
bin/shift digest --dry-run
```

`--dry-run` runs every phase for real - lock, timeout, guard, grading, receipt -
and stubs only the model call. Nothing is spent, nothing is changed. Read what
it left in `state/receipts/`, then run it again without the flag.

To put the rat into a project you already have:

```bash
./install.sh ~/code/your-project
```

It copies `CONTRACT.md`, `.claude/loops/`, `bin/`, and `kill.sh`, appends the
`state/` entries to that project's `.gitignore`, and touches nothing else.

---

## What one shift does

```
preflight → act → verify → guard → grade → receipt
```

**preflight** refuses to start if `state/HALT` exists, if today's spend is gone,
or if the same loop is already running - and a lock whose process is gone is
cleared rather than obeyed. Then it composes the brief: the
contract, your local overrides, the rubrics this loop is graded against, the
cursor the last shift left, and the plan.

**act** runs `act.sh` under a hard timeout. Facts are gathered by shell, judgment
is asked of the model - anything a script can determine should never cost a
token. stdout becomes `output.md`.

**verify** runs the plan's `verify:` command. This is the deterministic half of
"did it work". A model reporting that the tests pass is not evidence; the exit
code is.

**guard** compares the working tree against a fingerprint taken before the shift
started and blocks on four things: a change a loop's autonomy level does not
allow, a path from the denylist, more files than the blast radius allows, or
something shaped like a secret. Work you left on the branch yesterday is not
blamed on tonight's shift, and a shift writing its own receipt is not a change to
the repository.

**grade** hands the output to a second agent with a fresh context and the
rubrics. An agent grading its own shift always finds it excellent, which is why
the grader never sees itself as the author.

**receipt** writes `receipt.json`, appends one line per phase to `trace.log`, and
updates the checkpoint so tomorrow's shift knows where this one stopped.

A shift stopped by hand or by `kill.sh` still gets all of that: the receipt is
marked `interrupted` and says which phase it was cut off in. A night you cannot
reconstruct is worse than a night that failed.

Read it back:

```bash
bin/rat list           # what is scheduled, how often, how much it is trusted
bin/rat status         # last verdict per loop, today's spend, halt state
bin/rat watch          # follow a running shift, phase by phase, as it happens
bin/rat receipts 10    # the last ten shifts, newest first
bin/rat show           # the most recent receipt in full
bin/rat trace 40       # the phase log
bin/rat run <loop>     # one shift now, ignoring the schedule
bin/rat replay         # ask the same brief again, and compare the two answers
bin/rat prune          # age out old receipts, once you have too many
bin/rat doctor         # validate the machine and the configuration
```

Anything a script needs is machine readable: `rat status --json`, and
`rat receipts --json` with `--loop`, `--verdict` and `--since 3d` filters.

### When a shift surprises you

```bash
bin/rat replay state/receipts/2026-09-02/040012-test-mender
```

The saved brief is sent again, unchanged, and nothing is gathered a second time -
so any difference in the answer came from the model, not from the world moving.
The replay writes its own receipt, marked with the one it came from, and prints
how far the two answers agree. Two answers that agree point at the plan; two that
disagree point at a brief that is under-specified.

---

## The five loops that ship with it

| loop | cadence | autonomy | what it does |
|---|---|---|---|
| `pr-hunter` | every 30m, 09:00-19:00, weekdays | report-only | reads open PRs, says which one to look at first |
| `test-mender` | every 4h, overnight | assisted | fixes **one** failing test, or explains why it will not |
| `digest` | 06:45 on weekdays | report-only | turns last night's receipts into one page |
| `docs-drift` | 07:15 on weekdays | report-only | compares the CLI against its own documentation |
| `cost-watch` | 07:30 on Mondays | report-only | reads what the other loops cost and where they drift |

`docs-drift` and `cost-watch` are also the two clearest examples of the habit
that keeps loops cheap: both do their comparing in python, and call a model only
when there is something to judge. A clean `docs-drift` night costs nothing at
all.

They are examples, not the product. The shape is the product: a plan that names a
stop condition, an `act.sh` that gathers before it asks, a rubric that grades,
a receipt at the end.

### Autonomy is enforced, not implied

Every plan declares a level, and the guard holds it to it:

| level | may change files | a bad night costs you |
|---|---|---|
| `report-only` | no - any change blocks the shift | five minutes of reading |
| `assisted` | yes, within the blast radius | a `git checkout` |
| `autonomous` | yes, wider radius | a revert, and a bad afternoon |

A `report-only` loop that writes a file is blocked even when the change would
have been correct, because it said it would not and then did. An unknown level
is treated as the strictest one, so a typo in a plan can never widen what a loop
may do. The limits per level live in `settings.json`.

Start every loop at `report-only` and leave it there for a week of receipts you
actually read. [docs/loop-design.md](docs/loop-design.md) is the rest of that
argument.

Make your own:

```bash
bin/rat new release-notes
$EDITOR .claude/loops/release-notes/plan.md
bin/shift release-notes --dry-run
```

Then add it to `schedule.yml`. Details in [docs/writing-a-loop.md](docs/writing-a-loop.md).

---

## Where this is going

| version | the one sentence |
|---|---|
| **0.4** | read the night faster - `rat watch`, `rat replay`, a weekly digest |
| **0.5** | off the laptop - the tick runs in Actions, state travels on a branch |
| **0.6** | sharper graders - rubric packs, two graders, `rat calibrate` |
| **0.7** | the work itself - a worktree per shift, bounded repair, loop packs |
| **1.0** | trust - a hash-chained trace, autonomy per directory, `rat audit` |
| **never** | no dashboard, no database, no hosted service, no auto-merge |

Nothing becomes a default until a week of receipts says it should. The full
version, including why each refusal is a refusal, is in
[ROADMAP.md](ROADMAP.md).

---

## Scheduling

`bin/rat run-due` reads `schedule.yml` and the checkpoint, then runs whatever is
due - honouring each loop's interval, `at:` time, window, and days. Cron gets one
line and no rules of its own:

```bash
bin/rat cron                 # one tick, plus your schedule as comments
(crontab -l 2>/dev/null | grep -v 'bin/rat run-due'; bin/rat cron) | crontab -
```

Everything that decides whether a loop runs stays in `schedule.yml`. Pause a
loop, move its window, change its cadence - the next tick picks it up and the
crontab never needs editing.

Laptops sleep and cron does not catch up. `run-due` is idempotent by design: a
missed window is a skipped shift, never a backlog that fires all at once when you
open the lid. A daily loop with an `at:` time still runs once, late, rather than
not at all. For GitHub Actions, see
[.github/workflows/nightly.yml](.github/workflows/nightly.yml).

---

## Stopping it

```bash
./kill.sh "pr-hunter is spamming"
```

Kills whatever is running and writes `state/HALT`. Every scheduled shift refuses
to start while that file exists. Nothing is thrown away - the receipts of the
killed shift stay on disk. Start again with `bin/rat resume`.

The other three brakes, in the order they usually catch something:

- **spend** - `max_usd_per_day` is checked before a shift starts, and
  `max_usd_per_shift` before each model call within it. Neither can stop a call
  already in flight, which is what the timeout is for. A runaway loop runs out of
  allowance rather than out of money.
- **blast radius** - `max_files_changed`. A shift that wants an eleventh file
  when the limit is ten is blocked and reported, not quietly trimmed.
- **the denylist** - secrets, credentials, migrations, auth, billing, CI config,
  lockfiles. Enforced by [`bin/lib/guard.py`](bin/lib/guard.py), which is
  deterministic and has no opinion about how good the code was.

---

## What it costs

The three shipped loops run about **$2-4 a week** on Sonnet at their default
cadence. `bin/rat status` shows today's spend; `state/budget.json` keeps the
per-loop breakdown.

Two habits keep it there, and both belong in your own loops: `act.sh` gathers
with shell before it asks the model anything, and the grader sees only the output
and the diff, never the repository.

---

## Requirements

- bash 3.2 or newer (stock macOS is fine), python 3.8+, git
- an agent CLI on your PATH. The default is `claude`, configured under `agent` in
  `settings.json`. Anything that takes a prompt on stdin and returns JSON works -
  change `command`, `args`, and the two field names.
- optional: `gh`, used by `pr-hunter` when it is authenticated and skipped when
  it is not

With no CLI installed, every shift runs as a dry run and says so in the receipt.

---

## Tests

```bash
tests/smoke.sh
```

50 checks against a scratch copy of the harness: the parsers, the scheduling
rules, a full shift, the guard blocking a denied path and an oversized diff, the
lock refusing to overlap, the ledger refusing a spent day and refusing the next
model call, eight concurrent writers losing no spend, the kill switch, the
timeout killing a hung shift, and every subcommand. The model call is the only
thing stubbed.

---

## Reading order

- [docs/anatomy.md](docs/anatomy.md) - every file, and why it exists
- [docs/writing-a-loop.md](docs/writing-a-loop.md) - the plan, the act script, the stop condition
- [docs/safety.md](docs/safety.md) - what stops a shift, and in which order
- [docs/receipts.md](docs/receipts.md) - reading a morning's worth in two minutes
- [docs/loop-design.md](docs/loop-design.md) - the two questions, the autonomy ladder, the checklist
- [docs/failure-modes.md](docs/failure-modes.md) - how loops actually fail, and which brake catches each
- [ROADMAP.md](ROADMAP.md) - what comes next, and the four things that never will
- [CHANGELOG.md](CHANGELOG.md) - what has already landed, and why

MIT licensed. Take the parts you want.
