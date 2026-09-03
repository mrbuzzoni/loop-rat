# Changelog

## 0.4.0 - 2026-09-03

- **Autonomy is enforced.** `autonomy:` in a plan was a comment; it is now a
  rule the guard holds a loop to. A `report-only` loop that changes a file is
  blocked even when the change was correct, because it said it would not and
  then did. Levels and their blast radius live in `settings.json`, an unknown
  level is treated as the strictest, and the level is written into every
  receipt. The shift's brief now states the level in words, so the model is not
  guessing at it either.
- **`rat watch`** - follow a running shift phase by phase and see the report the
  moment it lands. The receipt tells you what happened; the watch tells you
  where a shift is spending its night, which is how you find out a loop is slow
  rather than stuck.
- **Two loops that watch this repository.** `docs-drift` compares the actual
  `case` block in `bin/rat` and the actual keys in `settings.json` against every
  markdown file, and calls a model only when there is a real difference to
  judge - a clean night costs nothing. `cost-watch` counts shifts, verdicts,
  timeouts, spend and the direction each is moving, and asks for five lines
  about it. Its first run found two undocumented commands and four unexplained
  settings keys, which are now documented.
- `rat list` shows each loop's autonomy next to its cadence, because "how often"
  and "how much is it trusted" are the two things you want in one glance.
- **Fixed:** the guard counted the harness's own receipts as changes to the
  repository. In a project that had not applied the gitignore block, every
  report-only loop was blocked by its own paperwork on the first night.
- New: [docs/loop-design.md](docs/loop-design.md) and
  [docs/failure-modes.md](docs/failure-modes.md). 70 checks in the smoke test.

## 0.3.3 - 2026-09-03

- **`bin/rat prune`.** Receipts pile up at a few kilobytes a shift and nothing
  removed them. It lists what has aged out and deletes only when asked twice
  (`--apply`), because a command that erases the record of unattended runs
  should not be a single keystroke.
- Two ages instead of one: `keep_days` (30) for shifts that passed,
  `keep_failed_days` (90) for anything blocked, failed, or waiting on review. A
  clean shift is evidence nobody read; the blocked one from July is what you go
  looking for in September.
- The test workflow also runs on Mondays now. A harness nobody pushes to still
  rots - a python release, a change in `git status` output - and hearing that
  from a scheduled run beats hearing it from a 3am shift.

## 0.3.2 - 2026-09-02

- **The schedule is the only schedule.** `bin/rat cron` installs one `run-due`
  tick instead of a line per loop, and prints the schedule as comments above it.
  A `window` or an `at:` time can no longer rot in the crontab while
  `schedule.yml` says something else.
- Daily loops honour `at:`. They fire once at or after that time and catch up
  late if the tick that should have caught them was missed, rather than firing at
  the first tick after midnight.
- `max_usd_per_shift` is actually enforced: it is checked before each model call,
  so a loop that asks twice cannot walk past its ceiling on the second question.
  It was documented as a cap and behaving as decoration.
- Agent arguments survive spaces. `args: ["--system-prompt", "be brief"]` used to
  arrive as three arguments.
- A timed-out shift kills its children, so the model call it had in flight does
  not outlive it.
- The spend ledger and the checkpoint are written under a lock. Two loops
  finishing in the same second used to lose one of the two entries.
- `state/*` with an unignored `.gitkeep`, so a state file added later cannot be
  committed by accident. The installer still writes an explicit list into a
  target repository, which may have a `state/` directory of its own - and now
  says so if it does.
- Smaller: no shift without a `CONTRACT.md`; `rat receipts` and `rat show` say
  when there is nothing to show; piping `rat status` into `head` no longer prints
  a python traceback; `guard.py` survives a machine with no git.

## 0.3.1 - 2026-09-02

- A failed model call is now recorded as a failed shift. It used to write an
  empty `output.md` and a `pass` verdict, which is the worst possible receipt:
  it looks like a quiet night.
- `RAT_ROOT` is always resolved from the harness's own location and never
  inherited. A harness running inside another harness - which happens the first
  time a loop runs your test suite - was writing receipts into the outer
  repository and pointing its kill switch at the wrong `state/`.
- `bin/rat cron` folds each loop's `window` into the crontab hour field, so a
  loop with `window: "09:00-19:00"` no longer fires at 3am and exits.
- Two shell values that were being interpolated into generated python now
  travel as environment variables. A `verify:` command containing a quote used
  to break the receipt writer.

## 0.3.0 - 2026-09-01

- **Grading.** A second agent with a fresh context reads the output against the
  rubrics and returns `pass`, `needs-review`, or `fail`. It is never told it is
  looking at its own model's work.
- **`digest` loop.** Reads last night's receipts and writes one page to
  `state/digest/<date>.md`. The thing that made the other loops worth keeping.
- **`install.sh`.** Drops the harness into an existing project without
  overwriting anything.
- `bin/rat show`, `bin/rat trace`, and `bin/rat new` from the template.

## 0.2.0 - 2026-08-29

- **The guard.** Deterministic gate over the denylist, the blast radius, and a
  secret scan. Compares against a fingerprint of the working tree taken before
  the shift, so uncommitted work from yesterday is not blamed on tonight.
- **The kill switch.** `kill.sh` stops what is running and writes `state/HALT`;
  nothing scheduled starts again until `bin/rat resume`.
- **The spend ledger.** Per-day and per-loop, checked before a shift starts.
- **Locks.** One shift per loop, `mkdir`-atomic, with stale locks cleared after
  the loop's own timeout.
- Portable timeout, because macOS ships no `timeout` binary and a shift without
  one is a bill without a ceiling.

## 0.1.0 - 2026-08-27

First working shift, start to finish: read `CONTRACT.md` and a plan, run
`act.sh` under a timeout, capture stdout, write a receipt folder, append to
`trace.log`, update the checkpoint.

Three loops to try the shape on: `pr-hunter`, `test-mender`, `digest`.
