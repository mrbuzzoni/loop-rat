# Roadmap

What the rat learns to do next, and what it will never learn.

Every item ships behind a flag it can be turned off with, and nothing becomes a
default until a week of receipts says it should. A feature that cannot be run as
a dry run does not get written. Anything that removes a brake is not a feature.

Shipped work lives in [CHANGELOG.md](CHANGELOG.md); this file is only the part
that has not happened yet.

## Standing today - v0.5.0

- the contract: rules committed, personal overrides gitignored
- the guard, the caps, `kill.sh`: denylist, blast radius, spend ledger, halt file
- autonomy levels the guard enforces, not a comment in a plan
- isolation: a shift can run in a worktree and arrive as a patch
- receipts and grading: one folder per shift, graded by a second agent
- five loops, 99 checks, no services

## 0.4 - read the night faster

The receipts are already right. Reading them is still slower than it should be.
Two of the four have landed; the digest rollup and `rat show --diff` are what
0.4 still owes.

| | |
|---|---|
| ~~**`rat watch`**~~ | **shipped in 0.4.0** - follow a running shift phase by phase, and read the report the moment it lands |
| ~~**`rat replay <receipt>`**~~ | **shipped in 0.4.1** - the saved brief again, unchanged, with a comparison of the two answers |
| **weekly digest** | seven nights on one page. The daily digest works; the pattern across a week is what tells you a loop is drifting |
| **`rat show --diff`** | the patch first, in your pager, and the prose about the patch second |

## 0.5 - off the laptop

A schedule that depends on a lid being open is not a schedule.

| | |
|---|---|
| **`run-due` in Actions** | the tick keeps time on a machine that does not sleep |
| **state on a branch** | laptop and CI share one checkpoint instead of disagreeing about what already ran |
| **`rat cron --launchd`** | macOS native, so a closed lid delays a shift rather than skipping the night |

## 0.6 - sharper graders

The grader is the part with an opinion, and opinions need calibration.

| | |
|---|---|
| **rubric packs** | per language and per repository, swappable, so a python project is not graded by a rubric written for a shell harness |
| **two graders, one verdict** | run two and let them disagree. Agreement is cheap; disagreement is the queue for your morning |
| **`rat calibrate`** | replay old receipts against a changed rubric and see which past verdicts flip. Edit rubrics with evidence, not with vibes |

## 0.7 - the work itself

Two of the three arrived early, because `test-mender` needed them before it was
safe to schedule. Loop packs are what is left.

| | |
|---|---|
| ~~**worktree per shift**~~ | **shipped in 0.5.0** - `worktree: true`, and `rat apply` to bring the patch in |
| ~~**bounded repair**~~ | **shipped in 0.5.0** - `repair: 1`, capped at two whatever a plan asks for |
| **loop packs** | install a loop someone else already ran for a month, with its rubric and stop conditions attached |

## 1.0 - trust

The version where someone other than the author can rely on the receipts.

| | |
|---|---|
| **hash-chained trace** | each line carries the hash of the last, so a receipt cannot be quietly rewritten. Including by an agent |
| **autonomy per directory** | per-loop levels landed in 0.4.0; this is the same idea per path, so one loop can be trusted in `docs/` and nowhere else |
| **`rat audit`** | a week of nights on one page, written for someone who was not there and has to decide whether to keep it running |

## Never

Not "not yet". These are refusals, and they are what keeps the rest small.

- **no web dashboard** - the terminal already knows where the files are.
- **no database** - plain files outlive the tool that wrote them.
- **no hosted service** - nothing to sign up for, nothing that can be shut down
  under you.
- **no auto-merge** - the rat proposes, the morning decides. A loop that merges
  its own work has no reader, and a loop with no reader is not a loop.

## How a version earns its place

```
dry run -> report only -> one repo -> a week of receipts -> default on
```

If you want something here sooner, or want to argue an item off the list, open
an issue with the receipt that made you want it. Roadmaps that move because of
evidence age better than roadmaps that move because of enthusiasm.
