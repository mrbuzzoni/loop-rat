#!/usr/bin/env python3
"""Config reader for the loop rat harness.

Reads the small, fixed subset of YAML this project uses (schedule.yml and the
front matter in every plan.md) plus settings.json, and prints the result as
JSON or as shell-safe key=value lines. No third-party dependencies: the harness
has to run on a bare machine at 3am.

Supported YAML subset:
    key: scalar
    key: [a, b, c]
    key:
      - name: x
        other: y
    # comments and blank lines
"""
import json
import os
import re
import signal
import sys

signal.signal(signal.SIGPIPE, signal.SIG_DFL)   # output is often piped to head

SCALAR_TRUE = {"true", "yes", "on"}
SCALAR_FALSE = {"false", "no", "off"}


def _scalar(raw):
    v = raw.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        if not inner:
            return []
        return [_scalar(p) for p in inner.split(",")]
    low = v.lower()
    if low in SCALAR_TRUE:
        return True
    if low in SCALAR_FALSE:
        return False
    if low in ("null", "~", ""):
        return None
    if re.fullmatch(r"-?\d+", v):
        return int(v)
    if re.fullmatch(r"-?\d+\.\d+", v):
        return float(v)
    return v


def parse_yaml(text):
    """Parse the supported subset into a dict."""
    root = {}
    current_list = None
    current_item = None
    list_indent = None

    for line_no, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        line = line.split("  #")[0].rstrip()
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()

        if stripped.startswith("- "):
            if current_list is None:
                raise ValueError("list item without a parent key on line %d" % line_no)
            list_indent = indent
            current_item = {}
            current_list.append(current_item)
            stripped = stripped[2:].strip()
            if not stripped:
                continue
            key, _, rest = stripped.partition(":")
            current_item[key.strip()] = _scalar(rest)
            continue

        key, sep, rest = stripped.partition(":")
        if not sep:
            raise ValueError("cannot read line %d: %r" % (line_no, line))
        key = key.strip()
        value = rest.strip()

        if current_item is not None and list_indent is not None and indent > list_indent:
            current_item[key] = _scalar(value)
            continue

        current_list = None
        current_item = None
        list_indent = None

        if value == "":
            current_list = []
            root[key] = current_list
        else:
            root[key] = _scalar(value)

    # A key that opened a block but never got list items is an empty mapping.
    for key, value in list(root.items()):
        if value == []:
            root[key] = []
    return root


def parse_front_matter(text):
    """Split `---` front matter from the prose body of a plan file."""
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    head = text[3:end].lstrip("\n")
    body = text[end + 4:].lstrip("\n")
    return parse_yaml(head), body


def emit_env(data, prefix):
    out = []
    for key, value in data.items():
        name = prefix + re.sub(r"[^A-Za-z0-9]", "_", str(key)).upper()
        if isinstance(value, bool):
            value = "1" if value else "0"
        elif isinstance(value, list):
            value = " ".join(str(v) for v in value)
        elif value is None:
            value = ""
        out.append("%s=%s" % (name, json.dumps(str(value))))
    return "\n".join(out)


def main(argv):
    if len(argv) < 3:
        sys.stderr.write(
            "usage: conf.py <yaml|front-matter|fm-get|body|json|get> <file> [key] "
            "[--env PREFIX]\n"
        )
        return 2

    mode, path = argv[1], argv[2]
    args = argv[3:]
    env_prefix = None
    if "--env" in args:
        i = args.index("--env")
        env_prefix = args[i + 1] if len(args) > i + 1 else "CFG_"
        args = args[:i] + args[i + 2:]

    if not os.path.exists(path):
        sys.stderr.write("conf.py: no such file: %s\n" % path)
        return 1
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()

    if mode == "yaml":
        data = parse_yaml(text)
    elif mode == "json":
        data = json.loads(text)
    elif mode == "front-matter":
        data, _ = parse_front_matter(text)
    elif mode == "body":
        _, body = parse_front_matter(text)
        sys.stdout.write(body)
        return 0
    elif mode in ("get", "fm-get"):
        if mode == "fm-get":
            data, _ = parse_front_matter(text)
        elif path.endswith(".json"):
            data = json.loads(text)
        else:
            data = parse_yaml(text)
        cursor = data
        for part in args[0].split("."):
            if isinstance(cursor, list):
                cursor = cursor[int(part)]
            else:
                cursor = cursor.get(part) if isinstance(cursor, dict) else None
            if cursor is None:
                return 1
        if isinstance(cursor, (dict, list)):
            print(json.dumps(cursor))
        elif isinstance(cursor, bool):
            print("1" if cursor else "0")
        else:
            print(cursor)
        return 0
    else:
        sys.stderr.write("conf.py: unknown mode %s\n" % mode)
        return 2

    if env_prefix:
        print(emit_env(data, env_prefix))
    else:
        print(json.dumps(data, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
