---
name: flaky-finder
autonomy: report-only
rubrics: [writing, safety]
timeout: 1800
max_usd: 0.20
verify: ""
---

# flaky-finder

A test that fails one run in twenty is worse than a test that always fails. The
always-failing one gets fixed on Tuesday. The other one teaches a team to rerun
the pipeline, and after a month nobody reads a red build at all.

`run.sh` has already run the suite several times in a row and recorded which
runs passed, which failed, and which test names appeared in the failures. It
changes nothing; it only runs the command you gave it.

## What to write

If every run agreed, one line saying so, with the count. Stop there.

If they did not:

```
3 of 8 runs failed, always in the same place:
  test/checkout.spec.ts "applies the discount"  - failed in runs 2, 5, 7
```

Then two sentences: what the pattern suggests (a shared fixture, a clock, a real
network call, an ordering assumption) and the single cheapest way to find out
for certain. Do not guess at the fix - name the experiment.

## Rules

- Never call a test flaky from a single failing run. That is just a failure.
- Report the runs, not a percentage. "3 of 8" is a fact; "38% flaky" is a
  decoration.
- If the whole suite failed every time, that is a broken build and not this
  loop's business. Say so and stop.
