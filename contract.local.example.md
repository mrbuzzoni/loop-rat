# contract.local.md

Copy this file to `contract.local.md` and it stops being an example: the harness
appends it to every prompt, after CONTRACT.md, and your lines win. It is
gitignored, so it never reaches the team's diff.

This is where the things that are true for you - and only you - go.

## Machine

- `npm test` needs `NODE_OPTIONS=--max-old-space-size=4096` on this laptop.
- The integration suite needs Docker running. If it is not, skip it and say so
  in the report rather than starting it.

## Preferences

- Do not reformat files you are not otherwise changing. My editor and the
  repository's formatter disagree and I have stopped caring.
- When two fixes are possible, take the one with fewer lines, not the one that
  is more clever.
- I read receipts on a phone. Keep the report under twenty lines.

## Temporary

- `src/legacy/billing/` is being rewritten this month by someone else. Do not
  touch it, do not report on it. Remove this line when their PR lands.
- Ignore the three flaky tests in `test/e2e/checkout.spec.ts`. Known, tracked,
  not yours.
