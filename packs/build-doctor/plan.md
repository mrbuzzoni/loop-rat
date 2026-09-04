---
name: build-doctor
autonomy: report-only
worktree: true
model: haiku
rubrics: [writing, safety]
timeout: 1800
max_usd: 0.50
verify: ""
---

# build-doctor

The most expensive bug in a fast-moving repository is not in the code. It is
that the code no longer installs. A dependency was added by hand, a step lives
only in someone's shell history, a file everyone has is not committed - and the
project keeps working for everybody who already has it working.

`check.sh` has already tried, in a clean checkout of the committed state: the
install step, then the build step, then the start or test step if there is one.
It ran nothing that was not already in the project.

## What to write

If every step passed, one line saying which steps ran, and stop. That is the
answer most days and it should take five seconds to read.

If a step failed:

```
npm ci  ->  failed
  the lockfile wants pg@8.11.5, the registry serves 8.11.3 for this range
  a fresh clone cannot install this project today
```

Then one line naming the smallest thing that would fix it - a file to commit, a
version to pin, a step to write down - and who has to do it.

## What matters here

- Only the clean checkout counts. "It works locally" is the failure being
  described, not a counter-argument to it.
- A missing file is the most common cause and the easiest to miss: a config that
  everyone has and nobody committed will look like a strange runtime error.
- Do not fix anything. This loop reports; someone reads it with the context of
  what they meant to do last week.

## Stop conditions

- every step passed. Say so in one line and stop.
- a step failed. Describe that one and stop - later steps failing because an
  earlier one did is noise.
