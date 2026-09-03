# Designing a loop

A loop is not a prompt on a timer. It is a small control system, and the parts
that make it safe are the boring ones: what starts it, what stops it, how much
it is trusted, and who reads the result.

## The two questions

Before anything else, answer both out loud:

**What starts a run?** A clock, a state change, or a person. If the honest answer
is "whenever I remember", you do not have a trigger, and a loop with no trigger
is a task you should do by hand.

**What ends a run?** Not "when it is finished" - name the observable condition.
The suite passes. Every open PR has a line. Two attempts produced the same
result. The blast radius is reached.

Most loops that go wrong went wrong at the second question. A loop with a vague
ending does not stop being wrong at 3am, it just keeps going.

## The autonomy ladder

Autonomy is declared in the plan's front matter and **enforced** by the guard.
It is not a comment about intent; a loop that exceeds its level is blocked and
its receipt says so.

| level | may change files | typical use | what a bad night costs you |
|---|---|---|---|
| `report-only` | no | triage, digests, drift reports, cost reviews | five minutes of reading |
| `assisted` | yes, within the blast radius | a fix per shift, reviewed in the morning | a `git checkout` |
| `autonomous` | yes, wider radius | narrow, well-verified, repeated work | a revert, and a bad afternoon |

Everything starts at `report-only`. Not for a day - for a week, with real
receipts you actually read. Promote a loop only when you have read seven
receipts and disagreed with none of them.

Each level's limits live in `settings.json` under `autonomy`, so tightening the
whole harness is one edit rather than one edit per loop. An unknown level is
treated as the strictest one: a typo can never widen what a loop may do.

Level answers "how much". `guard.path_policy` answers "where":

```json
{ "pattern": "src/payments/**", "min_level": "autonomous" },
{ "pattern": "docs/**",         "min_level": "assisted" }
```

A path can demand a higher level than any loop you have. That is the point - it
is how a directory stays out of reach of everything you have not deliberately
trusted with it, including loops you install later and forget about.

## Gather, then ask

The single habit that separates a cheap loop from an expensive one:

```bash
# deterministic, free, checkable later
python3 scan.py > "$RAT_RECEIPT/facts.md"

# judgment, and only judgment
{ cat "$RAT_RECEIPT/prompt.md"; cat "$RAT_RECEIPT/facts.md"; } | rat-agent --tag act
```

Anything a script can determine - file lists, test output, PR metadata, git
history, arithmetic - belongs in the script. It costs nothing, it is the same
every time, and it can be re-read months later without rerunning the shift.

The corollary: **a loop with nothing to do should cost nothing.** If the
gathering step finds no work, print that and exit before the model is called.
`docs-drift` does exactly this, and most of its nights are free.

## Where the work happens

A loop that may change files should change them somewhere you are not standing:

```yaml
worktree: true
```

The shift runs in a detached checkout under `state/worktrees/`, which is removed
when it ends. The diff survives in the receipt, and reaches your tree only when
you run `rat apply`. Three things follow from that, all of them good: your
editor never sees a file move under it, a bad night is deleted rather than
reverted, and the morning decision is explicit rather than implied.

The cost is that the shift cannot see uncommitted work you have not pushed to
that checkout. For a loop that fixes tests, that is usually a feature.

## One repair, never two

```yaml
verify: "npm test --silent"
repair: 1
```

If the check fails, the loop gets exactly one more attempt, with the failure
output and its own diff in front of it. The harness runs the check again
afterwards, and stops either way.

The ceiling is two repairs no matter what a plan asks for. A third attempt at
the same failure is not persistence - it is a loop that has stopped learning and
started guessing, and guessing at 3am is how repositories get damaged.

## Stop conditions that hold

Write them as facts that become true, not as amounts of effort:

```
good:  every open PR has a block. stop.
good:  two attempts produced the same failure. stop and report both.
good:  the verify command passes and nothing is left in scope. stop.
bad:   do your best, then wrap up.
bad:   fix the failing tests.
```

Three of them are enforced for you whatever the plan says: the timeout kills a
hung shift, the per-shift cap refuses the next model call, and the guard blocks a
diff that grew past the blast radius.

## Cadence

Match the interval to how fast the underlying thing changes, not to how eager
you are. A loop firing every fifteen minutes over a repository that changes twice
a day spends most of its shifts writing "nothing to do" - and you will start
skipping the receipts, which is the moment the loop stops being useful.

A daily loop with an `at:` time fires once at or after that time, and catches up
late if the machine was asleep. That is usually what you want for anything a
person reads over coffee.

## The reader

Every loop needs one, named before it is scheduled. If nobody would notice the
report missing for a week, do not build the loop. `cost-watch` exists precisely
because that question needs asking about the other loops, on purpose, on a
schedule.

## The checklist

Before you add a loop to `schedule.yml`:

- [ ] I can say what starts it and what ends it, in one sentence each
- [ ] Its autonomy is `report-only`, and will stay so for a week
- [ ] The deterministic part is in a script, not in the prompt
- [ ] It stops early and says so, rather than filling the timeout
- [ ] It has a rubric, and the rubric would fail a plausible bad night
- [ ] Someone reads its receipt, and I know who
- [ ] `bin/shift <name> --dry-run` produces a receipt I would be happy to read
