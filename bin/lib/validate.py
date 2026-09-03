#!/usr/bin/env python3
"""Check the harness's configuration the way a person would, but every time.

Reads settings.json, schedule.yml and every plan, and reports what would bite at
3am: a scheduled loop with no plan, a rubric that does not exist, an autonomy
level with a typo in it, a per-shift cap larger than the daily one, a verify
command that is not valid shell.

Prints one line per check. Exit 1 if anything is broken, 0 if only warnings.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from conf import parse_front_matter, parse_yaml   # noqa: E402

ROOT = os.environ.get("RAT_ROOT", ".")
LOOPS = os.path.join(ROOT, ".claude/loops")
KNOWN_LEVELS = ("report-only", "assisted", "autonomous")

problems = []
warnings = []


def ok(msg):
    print("  ok    %s" % msg)


def bad(msg):
    print("  FAIL  %s" % msg)
    problems.append(msg)


def warn(msg):
    print("  warn  %s" % msg)
    warnings.append(msg)


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def check_settings():
    path = os.path.join(LOOPS, "settings.json")
    try:
        settings = load_json(path)
    except (OSError, ValueError) as exc:
        bad("settings.json does not parse: %s" % exc)
        return {}

    caps = settings.get("caps", {})
    per_shift = float(caps.get("max_usd_per_shift", 0) or 0)
    per_day = float(caps.get("max_usd_per_day", 0) or 0)
    if per_shift <= 0 or per_day <= 0:
        bad("caps: both max_usd_per_shift and max_usd_per_day must be above zero")
    elif per_shift > per_day:
        bad("caps: a shift may spend $%.2f but the day only allows $%.2f"
            % (per_shift, per_day))
    else:
        ok("caps: $%.2f per shift inside $%.2f per day" % (per_shift, per_day))

    if int(caps.get("timeout_seconds", 0) or 0) <= 0:
        bad("caps.timeout_seconds must be above zero - a shift without a timeout "
            "is a bill without a ceiling")
    else:
        ok("caps.timeout_seconds is %ss" % caps["timeout_seconds"])

    levels = settings.get("autonomy", {})
    unknown = [k for k in levels if k not in KNOWN_LEVELS]
    if unknown:
        warn("autonomy: %s is not a level the harness knows; loops naming it will "
             "be treated as the strictest" % ", ".join(sorted(unknown)))
    missing = [lvl for lvl in KNOWN_LEVELS if lvl not in levels]
    if missing:
        warn("autonomy: no policy for %s - those loops fall back to no writes"
             % ", ".join(missing))
    if levels.get("report-only", {}).get("may_change_files"):
        bad("autonomy: report-only is configured to allow writes, which makes the "
            "level meaningless")
    elif levels:
        ok("autonomy: %d level(s) defined" % len(levels))

    if not settings.get("guard", {}).get("denylist"):
        warn("guard.denylist is empty - nothing is off limits by path")
    else:
        ok("guard.denylist covers %d pattern(s)"
           % len(settings["guard"]["denylist"]))

    agent = settings.get("agent", {})
    if not agent.get("command"):
        bad("agent.command is not set - the harness has nothing to call")
    else:
        ok("agent.command is %s" % agent["command"])
    return settings


def check_schedule(settings):
    path = os.path.join(LOOPS, "schedule.yml")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = parse_yaml(fh.read())
    except (OSError, ValueError) as exc:
        bad("schedule.yml does not parse: %s" % exc)
        return []

    loops = [l for l in (data.get("loops") or []) if isinstance(l, dict)]
    if not loops:
        warn("schedule.yml lists no loops - nothing will ever run on its own")
    scheduled = []
    for entry in loops:
        name = entry.get("name")
        if not name:
            bad("schedule.yml has an entry with no name")
            continue
        scheduled.append(str(name))
        every = str(entry.get("every", ""))
        if not re.fullmatch(r"\d+[mhd]", every):
            bad("%s: `every: %s` is not a cadence (use 15m, 4h, 1d)" % (name, every))
        window = entry.get("window")
        if window and not re.fullmatch(r"\d{1,2}:\d{2}-\d{1,2}:\d{2}", str(window)):
            bad("%s: window %r is not HH:MM-HH:MM" % (name, window))
        at = entry.get("at")
        if at and not re.fullmatch(r"\d{1,2}:\d{2}", str(at)):
            bad("%s: at %r is not HH:MM" % (name, at))
        if at and not every.endswith("d"):
            warn("%s: `at:` only applies to daily loops, and this one is %s"
                 % (name, every))
        if not os.path.isdir(os.path.join(LOOPS, str(name))):
            bad("%s is scheduled but has no folder in .claude/loops/" % name)
    if scheduled:
        ok("schedule.yml: %d loop(s), cadences readable" % len(scheduled))
    return scheduled


def check_plans(settings, scheduled):
    on_disk = []
    for name in sorted(os.listdir(LOOPS)):
        path = os.path.join(LOOPS, name)
        if not os.path.isdir(path) or name in ("rubrics", "_template"):
            continue
        on_disk.append(name)

        plan_path = os.path.join(path, "plan.md")
        act_path = os.path.join(path, "act.sh")
        if not os.path.exists(plan_path):
            bad("%s has no plan.md" % name)
            continue
        if not os.path.exists(act_path):
            bad("%s has no act.sh" % name)
            continue
        if not os.access(act_path, os.X_OK):
            bad("%s/act.sh is not executable (chmod +x it)" % name)

        with open(plan_path, "r", encoding="utf-8") as fh:
            front, body = parse_front_matter(fh.read())
        if not front:
            bad("%s/plan.md has no front matter" % name)
            continue
        if not body.strip():
            bad("%s/plan.md has front matter but no instructions" % name)

        level = str(front.get("autonomy", "report-only"))
        if level not in KNOWN_LEVELS:
            bad("%s: autonomy %r is not one of %s - it will be treated as the "
                "strictest" % (name, level, ", ".join(KNOWN_LEVELS)))

        for rubric in front.get("rubrics") or []:
            rubric_path = os.path.join(LOOPS, "rubrics", "%s.md" % rubric)
            if not os.path.exists(rubric_path):
                bad("%s names rubric %r, which does not exist" % (name, rubric))

        cap = front.get("max_usd")
        day_cap = float(settings.get("caps", {}).get("max_usd_per_day", 0) or 0)
        if cap is not None and day_cap and float(cap) > day_cap:
            bad("%s may spend $%s per shift, more than the whole day's $%.2f"
                % (name, cap, day_cap))

        timeout = front.get("timeout")
        if timeout is not None and int(timeout) <= 0:
            bad("%s: timeout must be above zero" % name)

        verify = str(front.get("verify") or "").strip()
        if verify:
            check = subprocess.run(["bash", "-n", "-c", verify],
                                   capture_output=True, text=True)
            if check.returncode != 0:
                bad("%s: the verify command is not valid shell (%s)"
                    % (name, check.stderr.strip().splitlines()[-1] if check.stderr else "?"))

        if name not in scheduled:
            warn("%s has a plan but is in no schedule - it only runs by hand" % name)

    if on_disk:
        ok("%d loop(s) on disk, plans and act scripts readable" % len(on_disk))
    return on_disk


def check_surroundings():
    contract = os.path.join(ROOT, "CONTRACT.md")
    if not os.path.exists(contract) or os.path.getsize(contract) == 0:
        bad("CONTRACT.md is missing or empty - a shift without rules is not a shift")
    else:
        ok("CONTRACT.md is %d bytes" % os.path.getsize(contract))

    if os.path.exists(os.path.join(ROOT, "contract.local.md")):
        ok("contract.local.md is present and will be appended to every brief")

    mcp = os.path.join(ROOT, ".mcp.json")
    if os.path.exists(mcp):
        try:
            load_json(mcp)
            ok(".mcp.json parses")
        except ValueError as exc:
            bad(".mcp.json does not parse: %s" % exc)

    git_dir = subprocess.run(["git", "-C", ROOT, "rev-parse", "--git-dir"],
                             capture_output=True, text=True)
    if git_dir.returncode != 0:
        warn("not a git repository - the guard cannot see what a shift changed")
    else:
        ok("git repository found, the guard can compare trees")

    trace = os.path.join(ROOT, "state", "trace.log")
    if os.path.exists(trace) and os.path.getsize(trace) > 5 * 1024 * 1024:
        warn("state/trace.log is over 5 MB - `rat prune` will rotate it")


def main():
    settings = check_settings()
    scheduled = check_schedule(settings)
    check_plans(settings, scheduled)
    check_surroundings()

    print()
    if problems:
        print("%d problem(s), %d warning(s)" % (len(problems), len(warnings)))
        return 1
    print("configuration is sound%s"
          % (", %d warning(s)" % len(warnings) if warnings else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
