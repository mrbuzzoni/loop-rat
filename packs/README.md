# Packs

Loops you can install into a project without writing them first.

```bash
bin/rat add --list          # what is here
bin/rat add todo-harvest    # copy it into .claude/loops/
```

`rat add` never overwrites an existing loop, validates what it copied, and
prints the schedule entry to paste. Nothing is scheduled for you: a loop that
starts running because you installed it is a loop nobody decided to run.

Every pack here ships `report-only`. Promote it yourself, after a week of
receipts you have actually read.

A pack is just a directory with a `plan.md` and an `act.sh`, so `bin/rat add
../some/other/loop` works too - that is the whole distribution mechanism, and it
is deliberately not a registry.
