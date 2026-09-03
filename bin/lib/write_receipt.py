#!/usr/bin/env python3
"""Write receipt.json - the one file a human is guaranteed to see.

Everything it needs arrives as environment variables so that no shell value is
ever interpolated into source code.
"""
import json
import os

env = os.environ
receipt = {
    "loop": env["RAT_LOOP"],
    "shift_id": env["RAT_SHIFT_ID"],
    "started": env["RAT_STARTED"],
    "ended": env["RAT_ENDED"],
    "duration_seconds": int(env["RAT_DURATION"]),
    "act": {
        "status": env["RAT_ACT_STATUS"],
        "exit_code": int(env["RAT_ACT_RC"]),
        "seconds": int(env["RAT_ACT_SECONDS"]),
    },
    "verify": {
        "status": env["RAT_VERIFY_STATUS"],
        "command": env.get("RAT_VERIFY_CMD", ""),
    },
    "guard": {
        "status": env["RAT_GUARD_STATUS"],
        "files_changed": int(env["RAT_CHANGED"] or 0),
    },
    "autonomy": env.get("RAT_AUTONOMY", "report-only"),
    "verdict": env["RAT_VERDICT"],
    "cost_usd": float(env["RAT_COST"] or 0),
    "dry_run": env.get("RAT_DRY_RUN", "0") == "1",
}
with open(os.path.join(env["RAT_RECEIPT"], "receipt.json"), "w") as fh:
    json.dump(receipt, fh, indent=2)
    fh.write("\n")
