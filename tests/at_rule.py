#!/usr/bin/env python3
"""Checks the one scheduling rule that is easy to get wrong.

A daily loop with `at: "06:45"` must fire once at or after that time, catch up
if the tick that should have caught it was missed, and not fire twice.
"""
import datetime
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCHEDULE = os.path.join(tempfile.mkdtemp(), "schedule.yml")
CHECKPOINT = os.path.join(os.path.dirname(SCHEDULE), "checkpoint.json")

now = datetime.datetime.now()
at_time = now - datetime.timedelta(minutes=30)
with open(SCHEDULE, "w") as fh:
    fh.write('loops:\n  - name: digest\n    every: 1d\n    at: "%s"\n'
             '    days: all\n    enabled: true\n' % at_time.strftime("%H:%M"))

target = now.replace(hour=at_time.hour, minute=at_time.minute,
                     second=0, microsecond=0).timestamp()


def due(last_epoch):
    with open(CHECKPOINT, "w") as fh:
        json.dump({"loops": {"digest": {"last_started_epoch": last_epoch}}}, fh)
    out = subprocess.run(
        [sys.executable, os.path.join(ROOT, "bin/lib/schedule.py"),
         "due", SCHEDULE, CHECKPOINT],
        capture_output=True, text=True,
    )
    return out.stdout.split()


cases = [
    ("never run", 0, True),
    ("last run yesterday", target - 86400, True),
    ("already ran today", target + 600, False),
]

failures = []
for label, last, expected in cases:
    got = "digest" in due(last)
    if got != expected:
        failures.append("%s: expected due=%s, got %s" % (label, expected, got))

if at_time.day != now.day:                      # ran within 30 minutes of midnight
    sys.exit(0)

for line in failures:
    sys.stderr.write(line + "\n")
sys.exit(1 if failures else 0)
