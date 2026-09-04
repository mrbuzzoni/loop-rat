# What people actually use this for

Five situations, written as they happen. Each one names the loops involved, what
a week of it costs, and the receipt you would read on the second morning.

If none of them is your situation, the last section is about deciding that a
loop is the wrong tool - which is a real answer and the cheapest one.

---

## 1. You ship fast and nothing is tested

**The situation.** You are building something with an agent, several times a day,
and it works. There are no tests, the README is three weeks behind the code, and
you have a quiet suspicion that a fresh clone would not run.

**What to run.** `build-doctor` twice a week and `secret-sweep` on Mondays.
Neither touches your code.

```bash
./install.sh ~/code/your-project
cd ~/code/your-project
bin/rat init
```

**What the second morning looks like.** Usually one line: everything still
installs. The morning it is not one line is the point of the whole thing:

```
npm ci  ->  failed
  the lockfile wants pg@8.11.5 and the registry serves 8.11.3 for this range
  a fresh clone cannot install this project today
```

You broke that eleven days ago. You would have found out when someone else tried.

**Cost.** Both loops do their work in shell and only call a model when something
is wrong. A quiet week is a handful of calls; a bad week is one call more.

---

## 2. You have tests and they keep going red overnight

**The situation.** Something in the suite fails intermittently. You rerun CI, it
passes, you move on. Three weeks later nobody reads a red build.

**What to run.** `flaky-finder` from the packs, nightly, off-hours:

```bash
bin/rat add flaky-finder
```

It runs your test command several times in a throwaway checkout and reports what
disagreed. It never calls a single failure flaky - that is just a failure.

**Then, and only then**, `test-mender` with `worktree: true` and `repair: 1`. It
fixes **one** failing test per night, in its own checkout, and leaves a patch:

```bash
bin/rat show --diff        # read the patch first
bin/rat apply              # put it in your tree, uncommitted
```

**The rule that makes this safe.** If the honest fix is "the test is wrong", the
loop is forbidden to edit the test. It writes down what the test asserts, what
the code does, and which one it believes - and stops. Deleting a test to make a
suite pass is a `fail` on the safety rubric and the work is thrown away unread.

---

## 3. You maintain something other people file issues against

**The situation.** Pull requests and issues arrive faster than you look at them.
Half of them need one sentence from you; you do not know which half.

**What to run.** `pr-hunter`, every four hours inside working hours. It reads
what is open and answers one question: which one should you look at first, and
why that one.

```
#128  fix: retry on 503   (opened 4d ago, checks: passing)
  state: waiting on you
  why:   approved twice, no conflicts, and it blocks #131
  next:  merge it, or say what is stopping you
```

It has no write access to anything. Nothing is merged, nothing is commented on,
nothing is closed. The output is a paragraph you read while the coffee is
brewing.

---

## 4. You are on the $20 subscription and want this to stay affordable

**The situation.** You do not pay per token. You pay a flat fee and share a
quota with your own interactive work, which is the thing you actually care about
not running out of.

**What to do.** `bin/rat init` defaults to exactly this - the `pro` profile:

- **twelve calls a day, counted** and refused after that. Not dollars: on a
  subscription the dollar figure a CLI reports is notional, and the real
  currency is calls against a quota you also need.
- **a small model for reading.** Grading is a fixed-shape reading task, so it
  runs on Haiku. A loop can name its own with `model: haiku` in the plan.
- **a quiet schedule.** Daily and weekly, never every fifteen minutes.
- **loops that exit before the call.** `secret-sweep`, `build-doctor`,
  `docs-drift` and `test-mender` all do their work in shell first and only ask a
  model when there is a judgment to make. A clean night costs nothing at all.

```bash
bin/rat status
```

```
today  $0.0000 spent of $12.00 cap
calls  3 of 12 today
```

If three calls a day is still too many, halve the schedule. A loop you cannot
afford to read is worse than no loop.

---

## 5. You inherited a repository and do not know what is in it

**The situation.** A codebase landed on you. It is large, it is someone else's,
and the fastest way to learn it is not to read it top to bottom.

**What to run**, in this order and each for a few days:

1. `secret-sweep` - what is in here that should not be, including in the history
2. `build-doctor` - does it install from clean, and which step is undocumented
3. `todo-harvest` - which notes-to-self are load-bearing and eighteen months old
4. `digest` - the week, on one page

None of them changes a file. After a fortnight you will have a map of the
project's soft spots that nobody wrote down, assembled while you slept.

---

## When a loop is the wrong answer

Be honest about this one, because the alternative is a schedule you stop reading.

- **The task happens once.** A one-off migration is not a loop. Do it in a chat
  window where you are watching.
- **You cannot say what would make it stop.** A loop with no observable ending
  does not become correct at 3am; it grinds until the timeout.
- **Nobody would notice the report missing for a week.** Then the loop has no
  reader, and a loop with no reader is a bill.
- **The thing it watches changes slower than the loop fires.** Most shifts will
  say "nothing to do", you will start skipping them, and the one that mattered
  goes with them.
- **It needs to be right rather than useful.** These loops propose. If the work
  must land without a person reading it, this is the wrong shape of tool and
  there is no flag that changes that.
