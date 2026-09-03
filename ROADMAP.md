# Roadmap

What the rat learns to do next, and what it will never learn.

Every item ships behind a flag it can be turned off with, and nothing becomes a
default until a week of receipts says it should. A feature that cannot be run as
a dry run does not get written. Anything that removes a brake is not a feature.

Shipped work lives in [CHANGELOG.md](CHANGELOG.md); this file is only the part
that has not happened yet.

## Standing today - v0.7.0

- the contract: rules committed, personal overrides gitignored
- the guard, the caps, `kill.sh`: denylist, blast radius, spend ledger, halt file
- autonomy levels the guard enforces, not a comment in a plan
- isolation: a shift can run in a worktree and arrive as a patch
- a hash-chained trace, so the record says whether it has been edited
- policy per path, so the harness's own code is out of reach of its loops
- installable packs, and two of them
- receipts and grading: one folder per shift, graded by a second agent
- five loops, two packs, 113 checks, no services

## 0.4 - read the night faster - shipped

The receipts were already right; reading them was the slow part. All four
landed: `rat watch`, `rat replay`, the weekly digest, and `rat show --diff`.

| | |
|---|---|
| ~~**`rat watch`**~~ | **shipped in 0.4.0** - follow a running shift phase by phase, and read the report the moment it lands |
| ~~**`rat replay <receipt>`**~~ | **shipped in 0.4.1** - the saved brief again, unchanged, with a comparison of the two answers |
| ~~**weekly digest**~~ | **shipped in 0.6.0** - the digest covers the whole week on Mondays |
| ~~**`rat show --diff`**~~ | **shipped in 0.6.0** - the patch first, the prose about it second |

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

## 0.7 - the work itself - shipped

All three landed: a worktree per shift, one bounded repair, and installable
packs.

| | |
|---|---|
| ~~**worktree per shift**~~ | **shipped in 0.5.0** - `worktree: true`, and `rat apply` to bring the patch in |
| ~~**bounded repair**~~ | **shipped in 0.5.0** - `repair: 1`, capped at two whatever a plan asks for |
| ~~**loop packs**~~ | **shipped in 0.7.0** - `rat add`, and two packs to start with |

## 1.0 - trust

Everything on this list has landed: the hash-chained trace, `rat audit`, and
policy per path.

**1.0 is not a feature list any more. It is a waiting period.** The rule this
project applies to its own loops applies to itself: nothing becomes a default
until a week of receipts says it should. The version number moves when the
harness has run unattended, on a real repository, for long enough that the
receipts are boring - and not on the day the last checkbox was ticked.

| | |
|---|---|
| ~~**hash-chained trace**~~ | **shipped in 0.6.0** - the chain is checked by `rat audit`, receipts included |
| ~~**autonomy per directory**~~ | **shipped in 0.7.0** - `guard.path_policy`, first match wins |
| ~~**`rat audit`**~~ | **shipped in 0.6.0** - the integrity check and the week, in one page |

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
