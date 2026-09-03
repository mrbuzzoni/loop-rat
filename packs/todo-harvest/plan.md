---
name: todo-harvest
autonomy: report-only
rubrics: [writing, safety]
timeout: 240
max_usd: 0.20
verify: ""
---

# todo-harvest

Every repository accumulates notes to a future self. Most of them are fine.
A few are load-bearing, were written eighteen months ago, and everyone has
stopped seeing them.

`scan.py` has already collected every TODO, FIXME, HACK and XXX marker, with the
file, the line, and how long it has been since that file was last touched. It
does not judge; that is your job.

## What to write

The five that matter, no more, each as one line:

```
src/auth/session.ts:212  FIXME  14 months untouched  - the marker says the token
                                 refresh is racy, and nothing since has changed it
```

Then a closing line naming the single one you would delete outright, because a
marker nobody will act on is worse than no marker: it makes the file look
supervised when it is not.

## What does not matter

- markers in files that changed this month - those are live notes, not debt
- `TODO: rename this` and other cosmetic ones
- markers inside test fixtures or vendored code

If none of them matter, say "nothing worth acting on" and stop. This loop earns
its place by being quiet most weeks.
