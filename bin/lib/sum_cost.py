#!/usr/bin/env python3
"""Add up what one shift spent, from the per-call cost files it left behind."""
import glob
import os
import sys

total = 0.0
for path in glob.glob(os.path.join(sys.argv[1], "agent-*.cost")):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            total += float(fh.read().strip() or 0)
    except (ValueError, OSError):
        pass
print("%.4f" % total)
