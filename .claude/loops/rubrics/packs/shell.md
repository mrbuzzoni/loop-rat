# Rubric pack: shell

Added automatically when a shift's diff touches `.sh` or `.bash`. Shell is where
an unattended change does the most damage per line, because everything is a
string until it is a command.

## Blocking

- An unquoted variable in a path, a test, or a command argument.
- `rm -rf` with a variable in the path that is not checked for emptiness first.
- A pipeline whose failure is silently swallowed - no `set -o pipefail`, no
  explicit status check.
- `cd` without either a subshell or a guaranteed return, in a script that
  continues afterwards.
- Parsing `ls` output, or looping over `$(ls)`.
- A new `sudo`, a new network call, or a new write outside the repository.
- Bash 4 syntax (`declare -A`, `${var,,}`, `mapfile`, `&>>`) in a script that
  claims to run on stock macOS, which ships bash 3.2.

## Quality

- `set -u` at minimum, and `set -e` only where every command's failure really is
  fatal.
- Quoting is consistent: `"$var"` everywhere, not on alternate lines.
- Long option names in scripts (`--force`), short ones only interactively.
- Errors go to stderr and exit non-zero. A script that prints "failed" and exits
  0 is worse than one that crashes.

## Verification

- The script was actually run, not only read. `bash -n` proves syntax, nothing
  more.
- If it takes a path or a name, it was run once with that argument missing.
