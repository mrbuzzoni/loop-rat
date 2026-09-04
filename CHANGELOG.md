# Changelog

## 0.10.0 - 2026-09-05

Aimed at the person this is most useful to and least built for so far: someone
shipping fast with an agent, on a flat subscription, who is not going to write a
plan file to get started.

- **`bin/rat init`.** Looks at the project, installs the loops that fit it,
  writes a quiet schedule, sets the caps for how you pay, and schedules nothing.
  Two profiles: `pro` (the default - the brake is calls) and `api` (dollars).
- **Calls are counted and capped**, because on a subscription that is what you
  actually spend. `caps.max_calls_per_day` refuses to start a shift once the
  day's calls are gone, `rat status` shows the count, and every attempt counts -
  including the ones that failed.
- **A loop can pick its own model.** `model: haiku` in a plan, or
  `grading.model` for the reading step, which is where the easy saving is.
- **Two packs for the repositories people actually have.** `secret-sweep` looks
  for committed credentials in the files and in the history, and never prints
  one - the finding is a position, because a receipt containing the key is a
  second copy of the leak. `build-doctor` tries the install, build and test
  steps in a clean checkout, which is how you find out that a fresh clone stopped
  working eleven days ago.
- **A discarded checkout is not a violation.** A report-only loop working in a
  worktree was blocked by its own `node_modules` and lockfile. Those cannot reach
  your repository, so they are recorded and not blocked - while an assisted
  loop's patch, which is meant to reach you, still is.
- **The installer no longer abandons a half-finished install** when an optional
  file is missing from the copy it was run from, and it no longer carries this
  repository's own loops or schedule into yours.
- New: [docs/scenarios.md](docs/scenarios.md) - five situations people use this
  for, what each costs, and when a loop is the wrong answer.
- 164 checks in the smoke test.

## 0.9.0 - 2026-09-05

The four things the roadmap still owed after 0.4 and 0.6.

- **The schedule can run off your laptop.** `bin/rat state pull|push` carries the
  checkpoint, the ledger, the hash-chained trace and the digests on an orphan
  branch of their own. A CI runner is a fresh checkout every time, and without
  that memory `run-due` thinks every loop is running for the first time, the
  daily cap resets on every run, and the chain restarts nightly - which is the
  same as not having one. `nightly.yml` now pulls, runs, pushes, and fails the
  run when the record does not add up.
- **Rubric packs per language, chosen by the diff.** A shift that touched `.py`
  is read against `rubrics/packs/python.md` without anyone remembering to ask for
  it; a shell repository never loads it. Packs extend `code.md`, so a loop graded
  only on prose gets none. Three ship: python, shell, javascript.
- **Two graders instead of one.** `grading.graders: 2` asks twice, independently.
  Agreement is the verdict; disagreement records the harsher one, keeps both
  readings, and puts the shift in a queue of its own - `rat receipts --disagreed`
  and a section in `rat audit`. Two careful readings parting company is a
  question about where the rubric draws its line, and that is worth a minute.
- **`rat calibrate`** - re-read old receipts against the rubrics as they are
  today and watch which verdicts move. A rubric is a prompt, so editing one is
  editing behaviour you cannot otherwise see. Originals are untouched unless you
  pass `--apply`.
- Grading moved out of `bin/shift` into `bin/grade`, so calibration repeats the
  real thing rather than an imitation of it.
- 147 checks in the smoke test.

## 0.8.0 - 2026-09-03

Everything here came from running the harness against a live model rather than
from reading the code.

- **A loop was blamed for a keystroke.** A report-only digest shift was blocked
  because a README was edited twenty-seven seconds after the shift fingerprinted
  the tree - the guard cannot tell your edit from the loop's when you share a
  tree. All shipped read-only loops now run with `worktree: true`, which removes
  the ambiguity structurally, `rat doctor` warns about report-only loops that
  lack it, and the guard says so plainly when it is judging a shared tree.
- **A transient failure no longer costs the night.** An overloaded API, a rate
  limit or a dropped connection is waited out with a longer pause each time; a
  permanent failure (bad credentials, a model that does not exist) is reported
  at once, because waiting will not help. Retries stop early rather than being
  killed mid-wait when the shift is nearly out of time, every attempt is billed,
  and only the final answer reaches the report.
- **The receipt no longer says "no usable JSON" when no grader ran.** Being out
  of budget, being in a dry run, and a grader that answered badly are three
  different sentences now.
- **Caps and timeouts match measured reality.** One call through the `claude`
  CLI cost $0.20-1.10 and took two to nine minutes here, so the shipped caps
  ($2.50 a shift, $12 a day) and timeouts (15-30 minutes) were raised to match,
  and `pr-hunter` was slowed from every 30 minutes to every 4 hours. The README
  now states measured numbers instead of an estimate.
- `rat-agent` fails with a usage line instead of hanging when stdin is a
  terminal.
- 129 checks in the smoke test.

## 0.7.1 - 2026-09-03

Found by auditing the harness rather than by adding to it.

- **Concurrent shifts broke the hash chain.** Two loops finishing in the same
  second each read the last trace line and appended, and the second one's hash
  pointed at a line that was no longer last. Trace writes are now serialized;
  four shifts racing each other leave a chain that holds.
- **An agent with no arguments crashed `rat-agent`** under `set -u` on the bash
  that ships with macOS. An agent that takes no flags is a normal agent.
- **An agent that produced nothing** ended in a python traceback instead of a
  receipt. It is now a failure with a sentence in `output.md`.
- **In-place shifts touched your index.** Building the patch staged everything
  and reset, which unstaged whatever you had staged yourself. The patch is now
  built through a private index, and contains only the files the guard saw the
  shift change - not work you left on the branch.
- `cost-watch` counted its own table header as a loop.
- Mutexes no longer look like shift locks to `kill.sh`, and a mutex left by a
  dead process is cleared after five seconds instead of slowing every write.
- 119 checks in the smoke test.

## 0.7.0 - 2026-09-03

- **A path can outrank a loop.** `guard.path_policy` maps globs to the minimum
  autonomy required to touch them, first match wins. In this repository `bin/`,
  `.claude/loops/`, `tests/` and `CONTRACT.md` now require `autonomous`, which
  no shipped loop is - so the harness's own code is out of reach of every loop
  it runs. `docs/` requires `assisted`.
- **Loop packs.** `bin/rat add --list` shows what is available, `bin/rat add
  <name>` installs it, validates it, and prints the schedule entry to paste.
  Nothing is scheduled for you: a loop that starts running because you installed
  it is a loop nobody decided to run. A pack is a directory with a `plan.md` and
  an `act.sh`, so `bin/rat add ../some/other/loop` works too - deliberately not
  a registry.
- Two packs to start with: `todo-harvest` (which markers are load-bearing and
  which are decoration) and `flaky-finder` (runs a command several times and
  reports what disagreed, never calling a single failure flaky).
- 113 checks in the smoke test.

## 0.6.0 - 2026-09-03

- **The log says whether it has been edited.** Every line of `trace.log` carries
  the hash of the line before it, and every receipt line carries the hash of the
  receipt as written. Change a line, delete one, or edit a receipt afterwards
  and the chain breaks at exactly that point.
- **`rat audit`** - recomputes both, then summarises the window and lists what
  still needs a person. It exits non-zero when the record does not add up, so it
  works as a monitoring check and not only as something you read. A rotated log
  is not treated as tampering: the first kept line has no predecessor left, and
  the audit says so.
- **`rat show --diff`** - the patch first, in full, and the prose about the patch
  second. The order you actually want when deciding whether to apply something.
- **The digest covers the week on Mondays.** One night tells you what happened;
  seven tell you whether a loop is drifting, and drift is what you cannot see one
  night at a time.
- Replays are attested like any other shift, so a receipt produced by
  `rat replay` cannot be edited unnoticed either.
- 105 checks in the smoke test.

  The reason for all of this is narrow and worth saying plainly: the harness runs
  an agent that can write to the same disk as its own evidence. A log only that
  agent can vouch for is not evidence.

## 0.5.0 - 2026-09-03

- **A shift can run somewhere you are not standing.** `worktree: true` in a plan
  puts the whole shift in a detached checkout under `state/worktrees/`, removed
  when it ends. Your editor never sees a file move under it, a bad night is
  deleted rather than reverted, and the work arrives in the morning as a patch
  in the receipt.
- **`rat apply`** - the other half of that. Read the receipt, check the patch
  still applies, put it in your working tree. Nothing is committed, nothing is
  pushed, and the command tells you how to undo it.
- **One repair, never two.** `repair: 1` gives a loop a second attempt after a
  failed check, with the failure output and its own diff in front of it, and
  runs the check again afterwards. The ceiling is two repairs whatever a plan
  asks for: a third attempt at the same failure is a loop that has stopped
  learning and started guessing.
- `test-mender` now ships isolated with one repair, which is what that loop
  should have been from the start.
- The validator knows the new keys: a `repair` with no `verify` is an error,
  a worktree on a report-only loop is pointless, and a repair above two is
  reported as the cap it will get.
- Works on the git that ships with older macOS: no `--quiet` on `worktree add`,
  and a manual prune when `worktree remove` is missing.
- 99 checks in the smoke test.

## 0.4.1 - 2026-09-03

- **An interrupted shift still leaves a receipt.** Ctrl-C and `kill.sh` used to
  end a night with a lock, a half-written folder and no record. Both now land in
  a signal handler that stops the child, writes a receipt marked `interrupted`
  with the phase it was cut off in, and releases the lock. A night you cannot
  reconstruct is worse than a night that failed.
- **`rat replay`** - send a saved brief again, unchanged, and compare the two
  answers. Nothing is re-gathered, so a difference came from the model rather
  than from the world moving. Answers that agree point at the plan; answers that
  disagree point at a brief with too much room in it.
- **`rat doctor` validates the configuration**, not just the machine. It reads
  every plan and the schedule and catches what would bite at 3am: a scheduled
  loop with no folder, a rubric that does not exist, `autonomy: report_only`
  with an underscore, a per-shift cap larger than the whole day's, a cadence
  that is not a cadence, a verify command that is not valid shell.
- **A lock whose process is gone is cleared, not obeyed.** Staleness was decided
  by the clock alone, so a crashed shift could hold its loop hostage for the
  length of its own timeout.
- `rat receipts` takes `--loop`, `--verdict`, `--since 3d` and `--json`;
  `rat status --json` prints the same state a status bar would want.
- `rat prune` rotates `trace.log` past twenty thousand lines. No shift trims its
  own log - a loop that edits the record of what it did is not auditable.
- 87 checks in the smoke test.

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
