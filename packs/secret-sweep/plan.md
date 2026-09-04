---
name: secret-sweep
autonomy: report-only
worktree: true
model: haiku
rubrics: [safety]
timeout: 600
max_usd: 0.50
verify: ""
---

# secret-sweep

The mistake that costs the most and takes one second to make: a key pasted into
a file to get something working, then committed. It is usually found by someone
else, usually later, and usually after it has been used.

`sweep.py` has already searched the tracked files and the recent history for
things shaped like credentials - provider keys, tokens, private key blocks,
connection strings with a password in them. It reports positions, never values.

## Your job

Separate the real ones from the noise, in one line each:

```
src/config.ts:14  an OpenAI key, live shape, committed 3 days ago
tests/fixtures/auth.json:7  a token, but every character is 'x' - a fixture
```

Then, if anything is real, the closing line says what to do first and in which
order: **rotate the key, then remove it from the file, then decide about the
history.** People do those backwards and rotate last, which is the one ordering
that does not help.

## Never do this

Do not print the secret. Not to show what you found, not as an example, not
partially. The receipt is a file on disk, and a receipt that contains the key is
a second copy of the leak. Name the file and the line and stop there.

## What is noise

- placeholders: `xxx`, `changeme`, `your-key-here`, `sk-test-...`
- fixtures and test doubles, when the surrounding file is clearly a fixture
- documentation showing the shape of a key rather than a key
- a `.env.example` with empty values

If everything found is noise, say "nothing real" in one line and stop.
