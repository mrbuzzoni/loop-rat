---
name: digest
autonomy: report-only
rubrics: [writing, safety]
timeout: 300
max_usd: 0.25
verify: ""
---

# digest

The loop that reads the other loops. It runs once, early, so that the first
thing on the screen in the morning is one page instead of a folder of receipts.

It changes no code. It writes one file: `state/digest/<date>-<window>.md`.

On Mondays the window is the whole week rather than one night. A single night
tells you what happened; seven tell you whether a loop is drifting, and drift is
exactly what you cannot see one night at a time. When you are writing the week,
lead with what changed across it - a loop that got slower, a verdict mix that
moved, a cost that crept - and treat individual nights as evidence for that
rather than as a list.

## What you are given

Every receipt from the window (24 hours, or the last week on Mondays): which loop ran, what verdict it got, what
it cost, and the first lines of what it reported. Plus anything the guard
flagged.

## What to write

Three parts, in this order, and no headings beyond these:

**Overnight** - two or three sentences. What ran, what came out of it, and
whether the night was ordinary. If it was ordinary, say that in one sentence and
move on. Most nights are ordinary and pretending otherwise trains the reader to
skip this file.

**Needs you** - a list, one line each, of the things that will not resolve
themselves. Every line names the decision, not the situation: "decide whether
the retry in fetch_user is worth keeping", not "there was a question about
fetch_user". If nothing needs a human, write "nothing" and stop the section.

**Ignore this if you are busy** - anything worth knowing but not worth acting
on today. Cost drift, a loop that keeps stopping early, a pattern across
shifts. Maximum three lines.

## Rules

- Never invent a number. Every figure comes from a receipt in front of you.
- A verdict of `needs-review` is not a failure and should not be described as
  one. Say what it means: a human has to look.
- If a loop did not run, that is more interesting than the ones that did. Lead
  with it.
- The whole file fits on a phone screen. If it does not, cut the third section.
