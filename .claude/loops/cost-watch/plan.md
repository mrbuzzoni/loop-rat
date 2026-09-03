---
name: cost-watch
autonomy: report-only
worktree: true
rubrics: [writing, safety]
timeout: 900
max_usd: 1.50
verify: ""
---

# cost-watch

The loop that watches the loops. Everything else in this repository looks at the
repository; this one looks at the night shift itself and asks whether it is
still worth what it costs.

`report.py` has already counted: shifts per loop, the verdict mix, timeouts,
average duration, average and total spend, the direction each of those is
moving, and how many shifts never started because they were locked out, halted,
or out of budget.

## What to write

Five lines, no headings, no table - the table is already above you.

1. **The night in one sentence.** Ordinary is a valid answer and the most common
   one.
2. **The loop that changed.** Whichever moved most: cost, duration, or verdict
   mix. Name the number it moved from and to.
3. **What that probably means.** A loop getting slower and more expensive at the
   same time is usually retrying. A loop that got cheap is usually finding
   nothing - which is either good news or a broken trigger.
4. **One dial to turn**, with the file and the value: a cadence in
   `schedule.yml`, a cap in `settings.json`, a stop condition in a plan.
5. **What to leave alone**, and why. Something is always tempting to tune and
   does not need it.

## Rules

- Never invent a number. Every figure is in the table above.
- A loop with fewer than four shifts has no trend. Say so instead of reading tea
  leaves.
- Skipped shifts matter more than slow ones. A loop that is locked out every
  night is doing nothing at all, and that is invisible in a cost table.
- Do not recommend turning off a brake. Timeouts, caps, and blast radius are not
  the dials in question - cadence and scope are.

## Stop conditions

- five lines written. Stop.
- fewer than four shifts on record in total: say the harness has not run enough
  to be worth reading, and stop.
