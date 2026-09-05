#!/usr/bin/env python3
"""Flatten a settings file or a plan's front matter into shell assignments.

  flatten.py json <settings.json> RAT_S_
  flatten.py front-matter <plan.md> RAT_P_

One python process instead of one per key. A shift reads two dozen settings, and
at fifty milliseconds each that was most of what a dry run spent its time on.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from conf import parse_front_matter  # noqa: E402


def emit(prefix, key, value):
    name = prefix + re.sub(r"[^A-Za-z0-9]", "_", key)
    if isinstance(value, bool):
        value = "1" if value else "0"
    elif isinstance(value, list):
        value = " ".join(str(v) for v in value)
    elif value is None:
        value = ""
    text = str(value).replace("'", "'\\''")
    # Exported, so a child process inherits the answers instead of asking again.
    print("export %s='%s'" % (name, text))


def walk(prefix, data, path=""):
    for key, value in data.items():
        if key.startswith("//"):
            continue
        full = ("%s.%s" % (path, key)).lstrip(".")
        if isinstance(value, dict):
            walk(prefix, value, full)
        else:
            emit(prefix, full, value)


def main(argv):
    if len(argv) < 4:
        sys.stderr.write(__doc__)
        return 2
    mode, path, prefix = argv[1], argv[2], argv[3]
    try:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return 1

    if mode == "json":
        try:
            data = json.loads(text)
        except ValueError:
            return 1
        walk(prefix, data)
    elif mode == "front-matter":
        front, _body = parse_front_matter(text)
        for key, value in front.items():
            emit(prefix, str(key), value)
    else:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
