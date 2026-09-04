# Rubric pack: javascript

Added automatically when a shift's diff touches `.js`, `.ts`, `.jsx`, `.tsx`,
`.mjs` or `.cjs`.

## Blocking

- A promise created and not awaited or returned - the error will surface as an
  unhandled rejection, far from here.
- `catch (e) {}` with an empty body, or one that only logs and continues as if
  nothing happened.
- `any` added to silence a type error rather than to describe a value, or a
  `@ts-ignore` with no comment saying why.
- A dependency added to `package.json`, or a lockfile edited.
- `==` where the file uses `===` everywhere else.
- A `useEffect` (or equivalent) whose dependency array was edited to stop a
  warning rather than to describe what it actually depends on.

## Quality

- Async errors are handled where they can be acted on, not swallowed at the top.
- Nullish coalescing and optional chaining used where the file already does.
- The change matches the module system in use - no `require` added to an ESM
  file, no `import` added to a CommonJS one.
- No new global state.

## Verification

- Tests run in the same runner the repository uses, not a new one.
- If the change touches rendering, something asserts on the rendered output
  rather than on the component's internals.
