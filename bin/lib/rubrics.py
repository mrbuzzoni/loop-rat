#!/usr/bin/env python3
"""Decide which rubrics a shift is graded against.

  rubrics.py <rubrics-dir> <diff.patch> code safety

Prints one rubric file path per line: the ones the plan named, plus a language
pack for every language the diff actually touched. A python fix is graded by
python rules without anyone having to remember to ask for them, and a shell
repository never sees the python pack.

Packs extend the `code` rubric, so a loop that is not graded on code does not
get them.
"""
import os
import re
import sys

# Extension to pack name. A pack is only pulled in if the diff touched a file
# with one of these suffixes, so an unused language costs nothing.
LANGUAGES = {
    ".py": "python",
    ".sh": "shell", ".bash": "shell",
    ".js": "javascript", ".jsx": "javascript",
    ".ts": "javascript", ".tsx": "javascript",
    ".mjs": "javascript", ".cjs": "javascript",
    ".go": "go",
    ".rs": "rust",
    ".rb": "ruby",
}


def languages_in(diff_path):
    if not diff_path or not os.path.exists(diff_path):
        return []
    found = []
    with open(diff_path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not line.startswith("+++ b/") and not line.startswith("--- a/"):
                continue
            path = line[6:].strip()
            _, ext = os.path.splitext(path)
            pack = LANGUAGES.get(ext.lower())
            if pack and pack not in found:
                found.append(pack)
    return found


def main(argv):
    if len(argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    rubrics_dir, diff_path = argv[1], argv[2]
    named = argv[3:]

    out = []
    for name in named:
        path = os.path.join(rubrics_dir, "%s.md" % name)
        if os.path.exists(path):
            out.append(path)

    if "code" in named:
        for pack in languages_in(diff_path):
            path = os.path.join(rubrics_dir, "packs", "%s.md" % pack)
            if os.path.exists(path):
                out.append(path)

    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
