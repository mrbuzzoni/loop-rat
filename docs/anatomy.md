# Anatomy

Every file in the rat, what it does, and why it is a separate file.

## The contract

**`CONTRACT.md`** - committed. Pasted at the top of every prompt, before the
loop's own job description. Rules that apply to all shifts: what may be touched,
what may never be, how to stop, what the report must contain.

It is committed so that loosening a rule shows up in a diff and gets reviewed
like code. That is the whole reason it is not a setting.

**`contract.local.md`** - gitignored, appended after the contract, and your lines
win. Machine quirks, personal preferences, temporary "do not touch this
directory this week" notes. Copy `contract.local.example.md` to start.

Two files instead of one because a team's rules and one developer's environment
have different lifespans. Mixing them means either committing your laptop's
memory flags or asking colleagues to respect a rule they never agreed to.

## The harness

**`.claude/loops/settings.json`** - the numbers, and the only file you edit to
retune the whole harness:

| key | what it decides |
|---|---|
| `agent.command`, `agent.args` | which binary is the model, and how it is called |
| `agent.result_field`, `agent.cost_field` | where in its JSON the answer and the price live |
| `agent.retries` | how many times a transient failure is waited out (a permanent one never is) |
| `agent.retry_delay_seconds` | the first pause; each retry waits longer, and none starts if the shift is nearly out of time |
| `autonomy.<level>` | what a loop at that level may change, and how much |
| `caps.max_usd_per_shift` | the ceiling checked before each model call |
| `caps.max_usd_per_day` | the ceiling checked before a shift starts at all |
| `caps.timeout_seconds` | how long an `act.sh` may run before it is killed |
| `caps.max_files_changed` | the default blast radius, when a level does not set one |
| `guard.denylist` | globs a shift may never touch |
| `guard.scan_secrets` | whether the diff is searched for keys and tokens |
| `grading.mode` | `auto` runs the second agent, `off` skips it |
| `receipts.keep_days`, `receipts.keep_failed_days` | what `rat prune` removes, and what it spares |

**`.claude/loops/schedule.yml`** - when each loop is eligible to run: `every`,
optional `at`, an hours `window`, `days`, and `enabled`. Both `bin/rat run-due`
and `bin/rat cron` read this file, so the schedule cannot drift from the crontab
you installed.

**`.claude/loops/rubrics/*.md`** - how work is graded. One file per kind of
output. They are prompts, not code: the grader is a second agent with a fresh
context that never sees itself as the author. `safety.md` is applied to every
shift; `code.md` and `writing.md` are opted into per loop.

**`.claude/loops/<name>/plan.md`** - one loop's job. Front matter carries the
machine-readable part (`rubrics`, `timeout`, `max_usd`, `verify`), the body is
the prompt. Written as instructions to a colleague, including the sentence that
tells them when to stop.

**`.claude/loops/<name>/act.sh`** - the actual work. Gathers facts with shell,
pipes one prompt into `rat-agent`, prints a report to stdout. Everything a script
can determine belongs here, not in the prompt: it is free, it is deterministic,
and it can be checked later without rerunning the shift.

**`.claude/loops/_template/`** - what `bin/rat new` copies.

**`packs/<name>/`** - loops that are not installed. `bin/rat add <name>` copies
one into `.claude/loops/` and prints the schedule entry to paste; it never
schedules anything itself. A pack is just a directory with a plan and an act
script, so a path to any other directory works the same way.

## The state

Nothing here is source. Delete the whole folder and the next shift rebuilds it;
you lose the history, never the setup.

**`state/receipts/<date>/<time>-<loop>/`** - one folder per shift:

| file | what it holds |
|---|---|
| `receipt.json` | the summary: verdict, duration, cost, exit codes |
| `prompt.md` | the exact brief that was sent |
| `output.md` | what the shift reported on stdout |
| `stderr.log` | what went wrong on the way |
| `guard.json` | which files changed, and any violation |
| `grade.json` | the second agent's verdict and its one-line note |
| `diff.patch` | the change, when there was one |
| `verify.log` | what the verify command printed |
| `cursor.json` | the resume point handed to the next shift |
| `tree-before.txt` | the working tree fingerprint taken before `act` |

**`state/trace.log`** - one append-only line per phase. The file you open when a
shift surprises you, because it is the only record written *while* things were
happening rather than after.

**`state/checkpoint.json`** - per loop: last verdict, last receipt, when it
started, and whatever cursor the loop wrote. `run-due` reads the timestamps to
decide what is due.

**`state/budget.json`** - spend per day and per loop.

**`state/worktrees/<loop>-<shift>/`** - the throwaway checkout an isolated shift
works in, removed when it ends. Present only while a shift is running, or after
one was interrupted before it could clean up - `git worktree prune` tidies those.

**`state/locks/<loop>.lock`** - a directory, because `mkdir` is atomic. Holds the
pid and the start time. A lock older than the loop's timeout is treated as stale
and cleared, so a crashed shift cannot block its loop forever.

**`state/HALT`** - written by `kill.sh`, checked by every shift before it starts.

## The commands

**`bin/rat`** - the front door: `list`, `run`, `run-due`, `watch`, `status`,
`receipts`, `show`, `trace`, `new`, `prune`, `cron`, `doctor`, `resume`,
`version`.

**`bin/shift`** - one shift, end to end. Everything that must happen in order -
lock, brief, act, verify, guard, grade, receipt - happens here and nowhere else.

**`bin/replay`** - sends a saved brief again and compares the two answers.

**`bin/rat-agent`** - the only place that talks to a model. One file, so
switching provider is one edit and every call is logged the same way.

**`bin/lib/`** - `common.sh` (paths, tracing, the portable timeout, locks, the
spend ledger), `conf.py` (settings, schedule, and plan front matter, no
dependencies), `schedule.py` (what is due, and the crontab tick), `guard.py`
(the deterministic safety gate), plus two small helpers that keep shell values
out of generated code.

## The edges

**`kill.sh`** - kills what is running and writes `state/HALT`. Deliberately at
the repository root, next to the README, where you can find it while annoyed.

**`.mcp.json`** - the tools a shift may reach. Anything not listed does not
exist as far as a shift is concerned. Start read-only and widen one server at a
time, after a week of receipts you were happy with.
