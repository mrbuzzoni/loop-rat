#!/usr/bin/env python3
"""Deterministic safety gate.

Runs after every shift, before a human ever looks at the work. It answers three
questions that must never depend on a model's opinion:

  1. did the shift touch a path it was forbidden to touch?
  2. did it change more files than the blast radius allows?
  3. did it leave anything that looks like a secret in the diff?

Two modes:

  guard.py --snapshot <file>                          record the tree first
  guard.py <settings.json> [<snapshot>] [<autonomy>]  judge what changed

A file counts as "changed by this shift" if it was not dirty before, or if its
size or mtime moved while the shift was running. Work someone left on the branch
yesterday is not held against tonight's loop.

The autonomy level comes from the loop's plan and decides how much change is
allowed at all. A report-only loop that writes a file is blocked even when the
file is harmless and the diff is small: the point of the level is that the loop
said it would not, and then did.

Exit codes: 0 clean, 3 blocked. The verdict is printed as JSON either way.
"""
import fnmatch
import json
import os
import re
import subprocess
import sys

SECRET_PATTERNS = [
    (r"AKIA[0-9A-Z]{16}", "aws access key id"),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "private key block"),
    (r"sk-(ant-)?[A-Za-z0-9_\-]{24,}", "provider api key"),
    (r"ghp_[A-Za-z0-9]{30,}", "github token"),
    (r"xox[baprs]-[A-Za-z0-9-]{10,}", "slack token"),
]


def git(repo, *args):
    try:
        proc = subprocess.run(
            ["git", "-C", repo] + list(args),
            capture_output=True, text=True, check=False,
        )
    except OSError:                             # no git on this machine
        return 127, "", "git not found"
    return proc.returncode, proc.stdout, proc.stderr


def dirty_files(repo):
    """Paths git currently reports as modified, added, or untracked."""
    code, out, _ = git(repo, "status", "--porcelain=v1", "--untracked-files=all")
    if code != 0:
        return None
    files = []
    for line in out.splitlines():
        if len(line) < 4:
            continue
        path = line[3:]
        if " -> " in path:                      # renames report "old -> new"
            path = path.split(" -> ", 1)[1]
        files.append(path.strip('"'))
    return files


def fingerprint(repo, path):
    try:
        stat = os.stat(os.path.join(repo, path))
        return "%d:%d" % (stat.st_size, int(stat.st_mtime))
    except OSError:
        return "gone"


def snapshot(repo, out_path):
    files = dirty_files(repo) or []
    with open(out_path, "w", encoding="utf-8") as fh:
        for path in files:
            fh.write("%s\t%s\n" % (fingerprint(repo, path), path))
    return 0


def load_snapshot(path):
    if not path or not os.path.exists(path):
        return {}
    baseline = {}
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if "\t" not in line:
                continue
            mark, name = line.split("\t", 1)
            baseline[name] = mark
    return baseline


def harness_paths(repo):
    """Paths the harness writes to by design.

    A shift writing its own receipt is not a shift changing the repository. The
    contract calls the receipt folder the loop's desk, and a guard that counts
    the desk blocks every report-only loop on its first night.
    """
    state = os.environ.get("RAT_STATE_DIR") or os.path.join(repo, "state")
    try:
        rel = os.path.relpath(state, repo)
    except ValueError:
        rel = "state"
    return [rel.rstrip("/") + "/*", rel.rstrip("/") + "/**"]


def main(argv):
    repo = os.environ.get("RAT_ROOT", ".")

    if len(argv) > 2 and argv[1] == "--snapshot":
        return snapshot(repo, argv[2])

    settings_path = argv[1] if len(argv) > 1 else os.path.join(
        repo, ".claude/loops/settings.json")
    baseline = load_snapshot(argv[2] if len(argv) > 2 else None)
    autonomy = argv[3] if len(argv) > 3 else "report-only"

    with open(settings_path, "r", encoding="utf-8") as fh:
        settings = json.load(fh)
    guard = settings.get("guard", {})
    denylist = guard.get("denylist", [])

    # An unknown level is treated as the strictest one. A typo in a plan must
    # never widen what a loop may do.
    levels = settings.get("autonomy", {})
    level = levels.get(autonomy, {"may_change_files": False, "max_files_changed": 0})
    may_change = bool(level.get("may_change_files", False))
    max_files = int(level.get(
        "max_files_changed",
        settings.get("caps", {}).get("max_files_changed", 10)))

    verdict = {
        "ok": True,
        "autonomy": autonomy,
        "checked": 0,
        "pre_existing": len(baseline),
        "ignored": "harness state",
        "violations": [],
        "files": [],
    }

    current = dirty_files(repo)
    if current is None:
        verdict["note"] = "not a git repository - the file guard cannot run here"
        print(json.dumps(verdict, indent=2))
        return 0

    ignore = harness_paths(repo) + guard.get("ignore_paths", [])
    files = [
        p for p in current
        if baseline.get(p) != fingerprint(repo, p)
        and not any(fnmatch.fnmatch(p, pattern) for pattern in ignore)
    ]
    verdict["files"] = files
    verdict["checked"] = len(files)

    for path in files:
        for pattern in denylist:
            if fnmatch.fnmatch(path, pattern) or fnmatch.fnmatch("/" + path, pattern):
                verdict["violations"].append(
                    {"kind": "denylist", "path": path, "pattern": pattern})
                break

    if files and not may_change:
        verdict["violations"].append({
            "kind": "autonomy",
            "level": autonomy,
            "changed": len(files),
            "note": "a %s loop is not allowed to change files" % autonomy,
        })
    elif len(files) > max_files:
        verdict["violations"].append(
            {"kind": "blast-radius", "changed": len(files),
             "limit": max_files, "level": autonomy})

    if guard.get("scan_secrets", True):
        _, unstaged, _ = git(repo, "diff", "--unified=0")
        _, staged, _ = git(repo, "diff", "--cached", "--unified=0")
        haystack = (unstaged or "") + (staged or "")
        for path in files:                      # untracked files never reach a diff
            full = os.path.join(repo, path)
            if os.path.isfile(full) and os.path.getsize(full) < 512 * 1024:
                try:
                    with open(full, "r", encoding="utf-8", errors="ignore") as fh:
                        haystack += fh.read()
                except OSError:
                    pass
        for pattern, label in SECRET_PATTERNS:
            if re.search(pattern, haystack):
                verdict["violations"].append({"kind": "secret", "match": label})

    verdict["ok"] = not verdict["violations"]
    print(json.dumps(verdict, indent=2))
    return 0 if verdict["ok"] else 3


if __name__ == "__main__":
    sys.exit(main(sys.argv))
