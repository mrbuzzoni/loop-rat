# Rubric: writing

Applied to shifts that produce prose - digests, release notes, issue summaries,
documentation. Prose written unattended drifts toward padding, so grade it the
way an editor would: by what can be cut.

## Blocking

- Every fact is traceable to something in the repository or the shift's own
  output. A plausible sentence with no source is a fabrication.
- Numbers match the source exactly. Not rounded, not "about".
- Nothing is presented as finished when it is in progress.
- No invented names, dates, or quotes.

## Quality

- The first sentence carries the news. If the reader stops there, they still
  know the most important thing.
- No throat-clearing. Cut "in this update", "it is worth noting", "as we can
  see", and every other sentence that only announces the next one.
- No sentence pairs of the form "this is not X, it is Y". No three-word
  fragments stacked for effect.
- Concrete over abstract: what changed, in which file, and who it affects.
- Sentence length varies. A page of identical-length sentences reads as machine
  output even when the facts are right.
- The piece ends when the information ends. No summary of what was just said.

## Verdict

- `pass` - accurate, and nothing in it could be cut without losing information.
- `needs-review` - accurate but padded, or one claim you could not trace.
- `fail` - anything unsourced, any number that does not match.
