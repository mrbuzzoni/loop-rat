---
name: docs-drift
autonomy: report-only
worktree: true
rubrics: [writing, safety]
timeout: 900
max_usd: 1.50
verify: ""
---

# docs-drift

Documentation rots quietly. A flag gets renamed, a command gets added, a setting
gets a second key, and the README keeps describing the tool as it was three
weeks ago. Nobody notices until a stranger follows the instructions and they do
not work.

This loop reads the **committed** state of the repository, not your working
copy - it runs in its own checkout. That is deliberate: drift is about what a
reader of this repository sees, and half-finished edits on your machine are not
that yet. It also means an edit you make while the loop is running is never
mistaken for something the loop did.

`scan.py` has already done the comparing. It reads the actual `case` block in
`bin/rat`, the actual keys in `settings.json`, and every markdown file in the
repository, and it separates four things: commands that exist but are documented
nowhere, commands the documents claim but the CLI does not have, commands only
the roadmap promises, and settings keys no document explains.

## Your job

Not to find the drift - it is in front of you. To say which of it matters.

For each item that matters, one line:

```
docs/receipts.md:  says `rat prune --all`, the flag is `--apply`
README.md:         never mentions `rat watch`, which is the command people ask for first
```

Then one closing line: the single edit that would fix the most confusing item,
written as an instruction someone can follow without opening the scanner output.

## What does not matter

- a command only the roadmap promises - that is a plan, not a lie
- an internal setting nobody outside this repository would ever set
- a document that uses a word like "prune" in a sentence rather than as a command

If everything the scanner found falls into those categories, say "nothing worth
fixing" in one line and stop. A report that lists ten harmless differences trains
the reader to skip the eleventh, which will be the one that mattered.

## Stop conditions

- every item that matters has a line. Stop.
- the scanner found nothing. Stop before writing anything else.
