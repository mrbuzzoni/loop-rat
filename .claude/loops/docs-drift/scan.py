#!/usr/bin/env python3
"""Compare what the harness can do against what the documentation claims.

Deterministic on purpose: the model is never asked what commands exist, only
what the differences mean. Prints markdown for the shift's brief.
"""
import json
import os
import re
import sys

ROOT = os.environ.get("RAT_ROOT", ".")
DOCS = ["README.md", "ROADMAP.md", "CHANGELOG.md", "CONTRACT.md"]
DOC_DIRS = ["docs"]


ROADMAP_HEADINGS = ("## where this is going", "## roadmap")


def read(path, drop_roadmap=True):
    try:
        with open(os.path.join(ROOT, path), "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return ""
    if not drop_roadmap:
        return text
    # A command named inside a roadmap section is a promise about the future.
    # Reading it as a claim about today turns every plan into a false positive.
    out, skipping = [], False
    for line in text.splitlines():
        low = line.strip().lower()
        if low.startswith("## "):
            skipping = low in ROADMAP_HEADINGS
        if not skipping:
            out.append(line)
    return "\n".join(out)


def doc_files():
    files = [d for d in DOCS if os.path.exists(os.path.join(ROOT, d))]
    for directory in DOC_DIRS:
        full = os.path.join(ROOT, directory)
        for base, _dirs, names in os.walk(full):
            for name in sorted(names):
                if name.endswith(".md"):
                    files.append(os.path.relpath(os.path.join(base, name), ROOT))
    return files


def real_subcommands():
    """The case block in bin/rat is the only source of truth for the CLI."""
    text = read("bin/rat")
    block = text.split('case "${1:-}" in', 1)
    if len(block) < 2:
        return set()
    found = set()
    for line in block[1].splitlines():
        match = re.match(r"\s{2}([a-z][a-z-]*(?:\|[a-z-]+)*)\)", line)
        if match:
            for name in match.group(1).split("|"):
                if name and not name.startswith("-"):
                    found.add(name)
    return found - {"", "help"}


def documented_subcommands(files):
    """Only count commands written as code.

    Prose says "the rat proposes, the morning decides", and a scanner that reads
    that as a promised subcommand produces a report nobody trusts twice.
    """
    patterns = [
        r"`rat ([a-z][a-z-]+)",          # `rat status`
        r"`bin/rat ([a-z][a-z-]+)",      # `bin/rat status`
        r"^\s*(?:\$ )?bin/rat ([a-z][a-z-]+)",   # inside a fenced block
    ]
    mentioned = {}
    for path in files:
        text = read(path, drop_roadmap=(path != "ROADMAP.md"))
        for pattern in patterns:
            for match in re.finditer(pattern, text, re.M):
                mentioned.setdefault(match.group(1), set()).add(path)
    return mentioned


def settings_keys():
    try:
        data = json.loads(read(".claude/loops/settings.json"))
    except ValueError:
        return set()
    keys = set()

    def walk(node, prefix=""):
        if isinstance(node, dict):
            for key, value in node.items():
                if key.startswith("//"):
                    continue
                keys.add((prefix + "." + key).lstrip("."))
                walk(value, prefix + "." + key)
    walk(data)
    return keys


def main():
    files = doc_files()
    real = real_subcommands()
    documented = documented_subcommands(files)

    undocumented = sorted(real - set(documented))
    missing = [k for k in documented if k not in real]
    # A command that only the roadmap mentions is a promise, not a lie.
    planned = sorted(k for k in missing if documented[k] <= {"ROADMAP.md"})
    phantom = sorted(k for k in missing if k not in planned)

    keys = settings_keys()
    corpus = "\n".join(read(f) for f in files)
    unmentioned_keys = sorted(
        k for k in keys
        if k.count(".") <= 1 and k.split(".")[-1] not in corpus
    )

    print("### the cli as it actually is")
    print(", ".join(sorted(real)) or "(none found)")
    print()
    print("### commands the docs never mention")
    print("\n".join("- `rat %s`" % c for c in undocumented) or "- none")
    print()
    print("### commands the docs claim but the cli does not have")
    for name in phantom:
        print("- `rat %s` - claimed in %s" % (name, ", ".join(sorted(documented[name]))))
    if not phantom:
        print("- none")
    print()
    print("### commands only the roadmap promises (expected, not drift)")
    print("\n".join("- `rat %s`" % c for c in planned) or "- none")
    print()
    print("### settings keys no document explains")
    print("\n".join("- `%s`" % k for k in unmentioned_keys) or "- none")
    print()
    print("### documents scanned")
    print(", ".join(files))
    print()

    # The last line is for the shift script, not for a reader: promises the
    # roadmap makes are excluded, so a clean run really means nothing to do.
    actionable = len(undocumented) + len(phantom) + len(unmentioned_keys)
    print("drift-count: %d" % actionable)
    return 0


if __name__ == "__main__":
    sys.exit(main())
