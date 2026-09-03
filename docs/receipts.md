# Receipts

The morning routine. It should take two minutes, and if it takes longer than
that the loops are wrong, not the reading.

## Two minutes

```bash
bin/rat status
```

```
today  $0.4120 spent of $5.00 cap
shifts 38 receipts kept, 6 day(s) on disk

LOOP             LAST_VERDICT   LAST_RUN             RECEIPT
digest           pass           2026-09-02 06:45     state/receipts/2026-09-02/064500-digest
pr-hunter        pass           2026-09-02 18:30     state/receipts/2026-09-02/183000-pr-hunter
test-mender      needs-review   2026-09-02 04:00     state/receipts/2026-09-02/040012-test-mender
```

Three things to notice, in this order:

1. **A loop missing from the list, or with an old timestamp.** A loop that did
   not run is more interesting than one that did. Cron died, the laptop slept,
   the halt file is still there.
2. **`needs-review`.** Something wants your eyes. That is the system working, not
   failing.
3. **The spend.** A number that moved without the work moving means a loop is
   retrying.

Then read the digest, which is one page:

```bash
cat state/digest/$(date +%F).md
```

Then open what the digest told you to:

```bash
bin/rat show state/receipts/2026-09-02/040012-test-mender
```

## Reading one receipt

`receipt.json` first. Verdict, duration, cost, and three statuses:

```json
{
  "act":    { "status": "ok",   "exit_code": 0, "seconds": 84 },
  "verify": { "status": "pass", "command": "npm test --silent" },
  "guard":  { "status": "ok",   "files_changed": 2 },
  "verdict": "needs-review",
  "cost_usd": 0.19
}
```

`act ok` means the script finished. `verify pass` means the repository agreed.
`guard ok` means nothing forbidden was touched. The verdict is the grader's, and
it is the only one of the four with an opinion.

Then, in order of how often they are the answer:

- **`output.md`** - what the shift reported. If the contract is doing its job,
  this is four short sections and you can stop here.
- **`grade.json`** - the grader's verdict and its one useful sentence
  (`fix_first`).
- **`diff.patch`** - the actual change. Read this before you read any prose
  about the change.
- **`guard.json`** - which files moved, and any violation.
- **`stderr.log`** - when something did not work.
- **`prompt.md`** - the exact brief that was sent. When a shift does something
  baffling, the answer is almost always in here: the contract said something you
  did not remember writing, or the cursor from the previous shift carried a
  stale assumption forward.

## When a shift surprises you

`trace.log` is the only file written while things were happening rather than
after:

```
2026-09-02T04:00:12Z loop=test-mender shift=040012 phase=preflight status=ok timeout=900s cap=$1.00 dry=0
2026-09-02T04:01:36Z loop=test-mender shift=040012 phase=act status=ok after=84s
2026-09-02T04:01:52Z loop=test-mender shift=040012 phase=verify status=pass cmd=npm test --silent
2026-09-02T04:01:52Z loop=test-mender shift=040012 phase=guard status=ok
2026-09-02T04:02:04Z loop=test-mender shift=040012 phase=grade status=needs-review score=72
2026-09-02T04:02:04Z loop=test-mender shift=040012 phase=receipt status=needs-review cost=$0.19
```

Phases that never appear are the interesting ones. No `act` line means the shift
died before it started - halted, locked, or out of budget, and the `preflight`
line says which.

## When you need to trust it

```bash
bin/rat audit --days 7
```

Every trace line carries the hash of the line before it, and every receipt line
carries the hash the receipt had when it was written. `rat audit` recomputes both
and says whether anything was edited or removed afterwards - then summarises the
window and lists what still needs a person.

It exits non-zero when the record does not add up, so it works as a monitoring
check rather than only as something you read. A rotated log is not an error: the
first kept line has no predecessor left, and the audit says so instead of crying
tampering.

The reason this exists is narrow and worth stating plainly: the harness runs an
agent that can write to this disk. A log that only that agent can vouch for is
not evidence.

## When you need to ask again

```bash
bin/rat replay state/receipts/2026-09-02/040012-test-mender
```

Same brief, sent again, nothing re-gathered. The replay lands in its own receipt
marked `replay_of`, and prints a short comparison: verdicts, files changed, cost,
and how much of the text the two answers share.

A high similarity means the plan produced the behaviour and you should edit the
plan. A low one means the brief left too much room, and the fix is a tighter
output shape or a firmer stop condition - not a better model.

## Housekeeping

Receipts are gitignored and cost a few kilobytes a shift. Nothing deletes them
on a schedule, on purpose - a cleanup loop that runs unattended and removes the
evidence of unattended runs is the one loop you should not build first. Pruning
is a thing you do, with your hands, when you decide to:

```bash
bin/rat prune            # lists what has aged out, deletes nothing
bin/rat prune --apply    # actually removes them
```

Two ages, set in `settings.json` under `receipts`:

| setting | default | applies to |
|---|---|---|
| `keep_days` | 30 | shifts that passed |
| `keep_failed_days` | 90 | blocked, failed, needs-review, unreadable |

The split is the whole point. A clean shift is evidence you never read. The one
that was blocked in July is the one you go looking for in September, when
something similar happens and you want to know what you decided last time.
