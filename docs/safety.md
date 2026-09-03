# Safety

What stops a shift, in the order it gets stopped.

A loop is only as safe as the thing that turns it off. Every brake below is
deterministic - none of them asks a model for an opinion, and none can be talked
out of it by the shift it is stopping.

## 1. The halt file

`state/HALT` is checked before anything else happens. While it exists, every
shift exits immediately with code 75 and writes a line to the trace.

```bash
./kill.sh "reason"    # kills what is running, writes HALT
bin/rat resume        # removes it
```

`kill.sh` sends SIGTERM to the running shift and its children, waits, then
SIGKILL, and clears the lock. It never deletes work: the receipt of the killed
shift stays where it was.

A panic button you are afraid to press is not a panic button, so this one is
reversible and leaves evidence. Press it early.

## 2. The spend ledger

`state/budget.json` holds today's total, per day and per loop. A shift refuses to
start when `max_usd_per_day` is gone, before it composes a prompt. `max_usd` in a
plan overrides `max_usd_per_shift` for that loop, and is checked before each
model call the shift makes - so a loop that asks twice cannot walk past its
ceiling on the second question. Neither cap can stop a call already in flight;
that is the timeout's job.

The day cap is the one that saves you. A loop that has learned to fail and retry
burns money at exactly the rate it burns time, and the day cap is the only brake
that does not depend on you noticing.

## 3. The lock

`state/locks/<loop>.lock` is a directory, because `mkdir` is atomic. A second
shift of the same loop exits 75 rather than racing the first. A lock older than
the loop's timeout is stale by definition and gets cleared, so a crash cannot
block its own loop forever.

Different loops still run concurrently. If two of yours can touch the same files,
give them windows that do not overlap - the harness will not sequence them for
you.

## 4. The timeout

Every `act.sh` runs under a watchdog (macOS ships no `timeout` binary, so the
harness carries its own). At the cap it sends SIGTERM, waits three seconds, then
SIGKILL. The verify command gets the same treatment.

A killed shift still produces a receipt, with `act.status = timeout`. That is
the point: the expensive failure mode is a shift that hangs silently and is
discovered two days later.

## 5. The guard

`bin/lib/guard.py` runs after every shift, before anything is graded, and blocks
on four things:

- **autonomy** - the level declared in the loop's plan. `report-only` means no
  file in the repository may change, and a loop that changes one is blocked even
  when the change was correct. `assisted` and `autonomous` set their own blast
  radius in `settings.json`. An unknown level is treated as the strictest, so a
  typo cannot widen a loop's reach.

- **denylist** - the glob list in `settings.json`. Ships covering `.env`,
  `secrets/`, `credentials/`, key and secret filenames, `migrations/`, `auth/`,
  `billing/`, `payments/`, `terraform/`, production k8s manifests, CI workflow
  files, and lockfiles.
- **blast radius** - more changed files than `max_files_changed`.
- **secrets** - AWS key ids, private key blocks, provider API keys, GitHub and
  Slack tokens, matched in the diff and in new files.

It compares against a fingerprint of the working tree taken before `act` ran, so
only what the shift itself touched counts. The harness's own `state/` directory
is excluded: a shift writing its receipt is not a shift changing the repository. Changes you left on the branch
yesterday are not held against tonight's shift, and a file that was already dirty
still counts if the shift modified it again.

A blocked shift exits 3 and is marked `blocked` in the receipt. Nothing is
reverted automatically - the harness stops, it does not tidy up after itself, and
what to do with a blocked diff is a decision for a person.

## 6. The grader

The last gate, and the only one with an opinion. A second agent, fresh context,
rubrics in front of it, and no knowledge that it is grading its own model. It
returns `pass`, `needs-review`, or `fail`.

`needs-review` is the honest default and should not be read as failure. It means:
correct as far as the grader could tell, and a person should look.

Grading can be turned off (`grading.mode: "off"`), which halves the cost of a
shift and removes the only check on the parts of the work no script can see. Not
recommended past week one.

## What is not protected

Worth being explicit, because a list of brakes reads as more coverage than it is:

- **The rat does not sandbox anything.** `act.sh` runs with your user's
  permissions. The denylist stops a shift from *committing* damage into scope, it
  does not stop a determined script from writing anywhere on your disk. Run it on
  a repository you would let a new contractor clone.
- **It does not manage credentials.** Whatever your agent CLI is authenticated
  as, the shift is authenticated as.
- **It does not review the model's reasoning**, only its output and its diff.
- **Nothing is reverted for you.** Blocked and failed work stays in the working
  tree, deliberately, so you see what happened.

## The order to relax things

Start every new loop at report-only with no `verify` and an `act.sh` that only
reads. Then, one step per week, never two at once:

1. let it write to a scratch file in `state/`
2. let it change one file in one directory, blast radius 1
3. raise the blast radius
4. widen the directories
5. let it run a verify command that can fail

If a step produces a receipt you disagree with, go back one and stay there a
week. The rat is worth having because it is boring. Keep it boring.
