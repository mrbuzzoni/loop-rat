# Failure modes

How unattended loops actually fail, and which part of the harness catches each
one. Written as a list of things to expect rather than things to fear: every one
of these is normal, and the point of the machinery is that none of them costs
you a morning.

## 1. The verifier gets gamed

**What it looks like.** The suite is green, the shift is proud, and the fix was
to delete an assertion, add a `sleep`, widen a type, or mark a test skipped.

**Why it happens.** The stop condition was "make the tests pass". That is a
condition about the test runner, not about the software, and the shortest path
to it does not go through the bug.

**What catches it.** `rubrics/code.md` blocks on it explicitly - a deleted,
skipped, or loosened test caps the verdict at `needs-review` no matter how good
the rest looks. The grader is a second agent with a fresh context, because a
shift grading its own work always finds it excellent.

**What you do.** Write stop conditions about behaviour, not about runners:
"the endpoint returns 404 for a missing user", not "the test passes".

## 2. Symptom patching

**What it looks like.** A null check appears where the null came from somewhere
three files away. Correct, green, and the same bug returns next week in another
shape.

**What catches it.** Nothing automatic, and it would be dishonest to claim
otherwise. `rubrics/code.md` asks the grader whether the report explains why the
value was null, and `bounded repair` on the roadmap will cap the attempts, but
this one is caught by the person reading the receipt.

**What you do.** Keep the blast radius small. A fix that must touch four files to
be correct will be reported rather than attempted, which is the outcome you want.

## 3. The retry spiral

**What it looks like.** The same failure, attempted eleven times, each attempt a
little more creative, the ledger climbing all night.

**What catches it.** Three brakes, in order: the per-shift cap refuses the next
model call, the timeout kills the shift, and the daily cap refuses to start the
next one. The plan should also name "two attempts, same result, stop" - but the
caps hold even when the plan forgets.

**What you do.** Read `state/budget.json`, or let `cost-watch` read it for you.
A loop whose cost and duration rise together is retrying, and that pair is the
clearest signal in the whole system.

## 4. Scope creep inside one shift

**What it looks like.** You asked for one failing test. The diff also renames
things, reformats a file, and fixes an unrelated warning that was bothering it.

**What catches it.** The blast radius, enforced by the guard against a
fingerprint of the tree taken before the shift started. Autonomy levels make it
sharper: a `report-only` loop that writes any file at all is blocked, even when
the change would have been correct - because it said it would not, and then did.

## 5. The loop that never runs

**What it looks like.** Nothing. No receipts, no errors, no signal. The most
expensive failure mode because it is invisible.

**Why it happens.** The lid was closed, `state/HALT` was never cleared, cron was
never installed, the window is wrong, or a stale lock is being respected.

**What catches it.** `rat status` shows the last run per loop, and a missing or
old timestamp is the first thing to look at. `cost-watch` counts shifts that
never started and names the reason. Locks older than the loop's own timeout are
cleared automatically, so a crash cannot block its loop forever.

## 6. The stale cursor

**What it looks like.** Tonight's shift confidently continues from a position
that stopped being true days ago - "last seen PR 118" when the repository has
moved on.

**What catches it.** Partly the plan: a cursor should record a fact, not a
conclusion. Mostly you, when a receipt says something that does not match the
repository.

**What you do.** Keep cursors small and factual. When a loop's meaning changes,
delete `state/checkpoint.json` - the next shift starts fresh and says so.

## 7. Receipt fatigue

**What it looks like.** Forty receipts, all `pass`, all unread. Then the one that
mattered goes unread too.

**Why it happens.** A loop that fires far more often than its subject changes,
or a report padded with detail nobody needs.

**What catches it.** The contract's four questions keep reports short. The digest
collapses a night into one page. `rat prune` keeps failures three times longer
than passes, because the interesting receipt is never the clean one.

**What you do.** Slow the cadence. This is almost always the answer, and almost
never the first instinct.

## 8. The loop blamed for your keystroke

**What it looks like.** A report-only loop is blocked for changing files it never
touched. The receipt accuses it; the diff is your own uncommitted work.

**Why it happens.** The guard fingerprints the tree before the shift and compares
afterwards. If you edit a file while the shift is running, that edit is inside
the window, and nothing in a file's timestamps says who made it.

**What catches it.** Nothing, if the loop and the person share a tree - which is
why the shipped read-only loops all run with `worktree: true`. A shift working in
its own checkout cannot be blamed for edits in yours, and the guard only ever
inspects the checkout. When a report-only loop is blocked while sharing your
tree, the guard now says so in the violation rather than letting the receipt
accuse the loop.

**What you do.** Put `worktree: true` on every loop that does not need to see
your uncommitted work. `rat doctor` warns about report-only loops that lack it.

This one was found by running the harness for real: a digest shift was blocked
because a README was edited twenty-seven seconds after the shift fingerprinted
the tree. The model's own report flagged it before the human did.

## 9. The harness inside the harness

**What it looks like.** A loop runs the test suite, the test suite runs the
harness, and receipts start appearing in the wrong repository.

**What catches it.** `RAT_ROOT` is always resolved from the harness's own
location and never inherited, so a nested run writes to its own `state/` and its
kill switch points at its own shifts. Found the hard way, fixed in 0.3.1, and
covered by the smoke test.
