#!/usr/bin/env python3
"""Reads schedule.yml and answers: which loop fires, and when.

Three commands:
  list <schedule.yml>                        - every loop and its cadence
  due  <schedule.yml> <checkpoint.json>      - loops that should run right now
  cron <schedule.yml> <repo_root>            - the crontab line to install

Cadence grammar: `every: 15m | 4h | 1d`, optional `at: "03:30"` for daily loops,
optional `window: "09:00-19:00"` and `days: mon-fri | all | sat,sun`.
"""
import json
import os
import subprocess
import signal
import sys
import time
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from conf import parse_yaml  # noqa: E402

signal.signal(signal.SIGPIPE, signal.SIG_DFL)   # output is often piped to head

DAY_NAMES = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]


def seconds(every):
    if every is None:
        return None
    text = str(every).strip().lower()
    unit = text[-1]
    try:
        amount = int(text[:-1])
    except ValueError:
        return None
    return {"m": 60, "h": 3600, "d": 86400}.get(unit, 0) * amount or None


def load(path):
    with open(path, "r", encoding="utf-8") as fh:
        data = parse_yaml(fh.read())
    loops = data.get("loops") or []
    return [l for l in loops if isinstance(l, dict) and l.get("name")]


def day_allowed(spec, now):
    if not spec or str(spec).lower() in ("all", "any", "daily"):
        return True
    today = DAY_NAMES[now.weekday()]
    spec = str(spec).lower().replace(" ", "")
    for part in spec.split(","):
        if "-" in part:
            start, end = part.split("-", 1)
            if start in DAY_NAMES and end in DAY_NAMES:
                si, ei = DAY_NAMES.index(start), DAY_NAMES.index(end)
                span = DAY_NAMES[si:ei + 1] if si <= ei else DAY_NAMES[si:] + DAY_NAMES[:ei + 1]
                if today in span:
                    return True
        elif part == today:
            return True
    return False


def window_allowed(spec, now):
    if not spec:
        return True
    try:
        start, end = str(spec).split("-", 1)
        sh, sm = [int(x) for x in start.split(":")]
        eh, em = [int(x) for x in end.split(":")]
    except ValueError:
        return True
    minutes = now.hour * 60 + now.minute
    start_m, end_m = sh * 60 + sm, eh * 60 + em
    if start_m <= end_m:
        return start_m <= minutes <= end_m
    return minutes >= start_m or minutes <= end_m       # window crosses midnight


def cmd_list(path):
    for loop in load(path):
        print("\t".join([
            str(loop.get("name")),
            str(loop.get("every", "-")),
            str(loop.get("window", "always")),
            str(loop.get("days", "all")),
            "enabled" if loop.get("enabled", True) else "paused",
        ]))
    return 0


def cmd_due(path, checkpoint_path):
    now = datetime.now()
    state = {}
    if os.path.exists(checkpoint_path):
        try:
            with open(checkpoint_path, "r", encoding="utf-8") as fh:
                state = json.load(fh).get("loops", {})
        except (ValueError, OSError):
            state = {}

    for loop in load(path):
        name = loop["name"]
        if not loop.get("enabled", True):
            continue
        if not day_allowed(loop.get("days"), now):
            continue
        if not window_allowed(loop.get("window"), now):
            continue
        interval = seconds(loop.get("every"))
        last = state.get(name, {}).get("last_started_epoch")
        at = str(loop.get("at") or "")

        if at and ":" in at and interval and interval >= 86400:
            # A daily loop with a time on it fires once, at or after that time,
            # and not again until tomorrow - even if the tick that should have
            # caught it was missed because the machine was asleep.
            try:
                at_h, at_m = [int(x) for x in at.split(":")[:2]]
            except ValueError:
                at_h, at_m = 0, 0
            if (now.hour, now.minute) < (at_h, at_m):
                continue
            target = now.replace(hour=at_h, minute=at_m, second=0, microsecond=0)
            if last and float(last) >= target.timestamp():
                continue
            print(name)
            continue

        if interval and last and (time.time() - float(last)) < interval:
            continue
        print(name)
    return 0


def windows_path(path):
    """A Git Bash path is /c/code/thing; Task Scheduler needs C:\\code\\thing.

    cygpath ships with Git for Windows and does the translation properly,
    including the drive letter. Without it, print what we have and say so.
    """
    try:
        out = subprocess.run(["cygpath", "-w", path],
                             capture_output=True, text=True, check=False)
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except OSError:
        pass
    return path.replace("/", "\\")


def cadence_minutes(every):
    total = seconds(every)
    return int(total / 60) if total else None


def cmd_cron(path, root, flavour="auto"):
    """One scheduled tick, not one entry per loop.

    Everything that decides whether a loop runs - interval, window, days,
    enabled - lives in schedule.yml, and `run-due` reads it every time it fires.
    Emitting a line per loop would copy those rules into the crontab, where they
    would quietly rot the first time someone edited the schedule. The tick below
    is only how often the rat looks at the clock.
    """
    loops = load(path)
    active = [l for l in loops if l.get("enabled", True)]
    ticks = [cadence_minutes(l.get("every")) for l in active]
    ticks = [t for t in ticks if t]
    tick = min(ticks) if ticks else 15
    tick = max(5, min(tick, 60))

    runner = os.path.join(root, "bin", "rat")

    if flavour == "auto":
        flavour = "windows" if os.environ.get("RAT_OS") == "windows" else "cron"

    header = [
        "loop rat - generated by `bin/rat cron`",
        "the schedule itself lives in .claude/loops/schedule.yml:",
    ]
    for loop in loops:
        header.append("  %-16s every %-5s %-14s %-8s %s" % (
            loop["name"], loop.get("every", "-"),
            loop.get("window", "any hour"), loop.get("days", "all days"),
            "" if loop.get("enabled", True) else "(paused)"))
    header.append("edit that file and the next tick picks it up - "
                  "the schedule below never changes.")

    if flavour == "windows":
        # Quoting a bash command inside a schtasks argument inside cmd.exe is a
        # famous way to lose an evening. So: a one-line wrapper file does the
        # quoting once, and the scheduler only ever sees a path.
        wrapper = os.path.join(root, "bin", "loop-rat.cmd")
        wrapper_win = windows_path(wrapper)
        body = (
            "@echo off\r\n"
            "REM written by `bin/rat cron --windows`. Runs whatever the schedule\r\n"
            "REM says is due. Edit .claude/loops/schedule.yml, never this file.\r\n"
            'cd /d "%~dp0.."\r\n'
            'bash -lc "bin/rat run-due >> state/cron.log 2>&1"\r\n'
        )

        if "--write" in sys.argv:
            with open(wrapper, "w", newline="") as fh:
                fh.write(body)
            print(":: wrote %s" % wrapper)
        else:
            print(":: 1. save this as bin\\loop-rat.cmd")
            print("::    (or run `bin/rat cron --windows --write` and it is written for you)")
            print()
            for line in body.replace("\r", "").rstrip("\n").split("\n"):
                print("      %s" % line)
            print()

        for line in header:
            print(":: %s" % line)
        print()
        print(":: 2. register it, once, in a terminal that may add tasks:")
        print()
        print('      schtasks /create /tn "loop rat" /sc minute /mo %d /f /tr "%s"'
              % (tick, wrapper_win))
        print()
        print(':: to see it:   schtasks /query /tn "loop rat"')
        print(':: to stop it:  schtasks /delete /tn "loop rat" /f')
        return 0

    for line in header:
        print("# %s" % line)
    if tick >= 60:
        expr = "0 * * * *"
    else:
        expr = "*/%d * * * *" % tick
    print("%s cd %s && %s run-due >> state/cron.log 2>&1" % (expr, root, runner))
    return 0


def main(argv):
    if len(argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    command, path = argv[1], argv[2]
    if command == "list":
        return cmd_list(path)
    if command == "due":
        return cmd_due(path, argv[3] if len(argv) > 3 else "state/checkpoint.json")
    if command == "cron":
        flavour = "auto"
        for name in ("--windows", "--cron"):
            if name in argv:
                flavour = name.lstrip("-")
                argv = [a for a in argv if a != name]
        return cmd_cron(path, argv[3] if len(argv) > 3 else os.getcwd(), flavour)
    sys.stderr.write("schedule.py: unknown command %s\n" % command)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
