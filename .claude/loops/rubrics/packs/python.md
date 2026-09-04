# Rubric pack: python

Added automatically when a shift's diff touches `.py`. It extends `code.md` with
the mistakes that are specific to this language and easy to wave through in a
diff at 3am.

## Blocking

- A bare `except:` or `except Exception:` that swallows the error without
  re-raising, logging, or narrowing it.
- A mutable default argument (`def f(x=[])`, `def f(x={})`).
- A resource opened without a context manager where one would work.
- `assert` used for a runtime check that must hold in production - assertions
  vanish under `-O`.
- A change to a public function's signature with no caller updated in the same
  diff.
- `import *`, or an import added inside a function to dodge a circular import
  rather than fixing it.

## Quality

- Type hints that match the surrounding file's habits: all of them or none, not
  a lone annotated function in an unannotated module.
- Exceptions raised are specific enough for a caller to catch one thing.
- Comprehensions stay readable. A nested comprehension with a condition is a
  loop wearing a costume.
- New dependencies on the standard library only, unless the plan said otherwise.
- f-strings for formatting, unless the file consistently uses something else.

## Verification

- The test exercises the changed branch, not merely the module. A test that
  passes with the change reverted is not evidence.
- If the change is in a `try` block, there is a test for the failure path too.
