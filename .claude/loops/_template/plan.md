---
name: __NAME__
autonomy: report-only
rubrics: [safety]
timeout: 600
max_usd: 0.50
verify: ""
---

# __NAME__

One paragraph: what this loop is for, and what a person had to do by hand before
it existed. If you cannot write that paragraph, the loop is not ready.

## What you are given

Describe what `act.sh` collects before the model is called. Facts a script can
gather should never cost a token.

## What to produce

Be specific about the shape of the output. "A report" is not a shape. Show the
block, the table, or the four sentences you want back.

## Stop conditions

Name at least two, and make them checkable:

- the thing is done
- there is nothing to do
- you tried twice and got the same answer
- the work would exceed the blast radius in the contract

## Cursor

If this loop should remember anything between shifts, say what JSON to write to
`$RAT_RECEIPT/cursor.json`. Delete this section if it should not.
