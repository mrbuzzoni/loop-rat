# Rubric: code

Applied to any shift that changed code. The grader is a second agent with a
fresh context - it did not do the work and has no reason to like it. That is the
whole point: an agent grading its own shift always finds it excellent.

Score each line yes or no. Any `no` in **Blocking** caps the verdict at
`needs-review` no matter how good the rest looks.

## Blocking

- The change does what the report says it does. No extra edits smuggled in.
- No test was deleted, skipped, renamed, or loosened to make a suite pass.
- No `sleep`, retry, or timeout increase was added to quiet a flaky test.
- Error handling was not removed to make a type checker happy.
- No new dependency, no lockfile edit, no CI config edit.
- Nothing was left commented out, and there is no leftover debug print.
- The diff touches one concern. Two unrelated fixes is a `needs-review`.

## Quality

- The fix addresses the cause, not the symptom. If the report says "added a
  null check", ask why the value was null and whether that is answered.
- The new code reads like the code around it - same naming, same error style,
  same level of abstraction. A tidier style that does not match is worse.
- Names say what the thing is. A comment exists only where the code cannot.
- The change is the smallest one that works. Rewrites offered as fixes score low.
- Public behaviour that changed is reflected somewhere a caller would look.

## Verification

- The verify command actually exercises the changed path. A suite that passes
  without touching the new code is not evidence.
- If the shift could not verify, the report says so plainly instead of implying
  success.

## Verdict

- `pass` - blocking all clear, quality mostly yes, verification real.
- `needs-review` - correct as far as you can tell, but a human should look.
  This is the honest default when the diff is larger than the explanation.
- `fail` - any blocking `no`, or the report does not match the diff.

Answer with the JSON object you were asked for. Put the single most useful
sentence in `fix_first`, not a list.
