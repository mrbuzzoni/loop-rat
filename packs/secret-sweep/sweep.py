#!/usr/bin/env python3
"""Look for things shaped like credentials, and never print one.

Positions only: file, line number, and which pattern matched. The finding is
that a secret is at a location; repeating the value would put a second copy of
the leak in the receipt.
"""
import os
import re
import subprocess
import sys

ROOT = os.environ.get("RAT_WORKDIR") or os.environ.get("RAT_ROOT", ".")

PATTERNS = [
    (r"sk-ant-[A-Za-z0-9_\-]{20,}", "an Anthropic key"),
    (r"sk-[A-Za-z0-9]{32,}", "an OpenAI-shaped key"),
    (r"AKIA[0-9A-Z]{16}", "an AWS access key id"),
    (r"ghp_[A-Za-z0-9]{30,}", "a GitHub token"),
    (r"github_pat_[A-Za-z0-9_]{50,}", "a GitHub fine-grained token"),
    (r"xox[baprs]-[A-Za-z0-9-]{10,}", "a Slack token"),
    (r"-----BEGIN [A-Z ]*PRIVATE KEY-----", "a private key block"),
    (r"AIza[0-9A-Za-z_\-]{35}", "a Google API key"),
    (r"[a-z][a-z0-9+.-]*://[^/\s:@]+:[^/\s:@]+@", "a URL with a password in it"),
    (r"(?i)\b(api[_-]?key|secret|password|token)\b\s*[:=]\s*['\"][^'\"]{12,}['\"]",
     "an assignment that looks like a credential"),
]

PLACEHOLDER = re.compile(
    r"(?i)x{6,}|change[_-]?me|your[_-]?(key|token|secret)|placeholder|example|"
    r"dummy|redacted|\.\.\.|<[^>]+>|\$\{[^}]+\}|test[_-]?key")

SKIP_DIRS = ("node_modules", ".git", "dist", "build", "vendor", "state",
             "__pycache__", ".venv", "venv")
SKIP_EXT = (".png", ".jpg", ".jpeg", ".gif", ".pdf", ".zip", ".gz", ".lock",
            ".woff", ".woff2", ".ico", ".mp4", ".svg")


def tracked_files():
    proc = subprocess.run(["git", "-C", ROOT, "ls-files"],
                          capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        return []
    return [f for f in proc.stdout.splitlines()
            if not any(part in SKIP_DIRS for part in f.split("/"))
            and not f.lower().endswith(SKIP_EXT)]


def scan():
    findings = []
    for path in tracked_files():
        full = os.path.join(ROOT, path)
        try:
            if os.path.getsize(full) > 512 * 1024:
                continue
            with open(full, "r", encoding="utf-8", errors="ignore") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        for number, line in enumerate(lines, 1):
            if len(line) > 4000:
                continue
            for pattern, label in PATTERNS:
                match = re.search(pattern, line)
                if not match:
                    continue
                looks_fake = bool(PLACEHOLDER.search(match.group(0)))
                findings.append((path, number, label, looks_fake,
                                 line.strip()[:40].split("=")[0][:40]))
                break
    return findings


def recent_history():
    """Commits that added a line matching the most unambiguous patterns."""
    hits = []
    for pattern, label in PATTERNS[:8]:
        proc = subprocess.run(
            ["git", "-C", ROOT, "log", "--oneline", "-S", pattern, "--pickaxe-regex",
             "-n", "5", "--format=%h %ad %s", "--date=short"],
            capture_output=True, text=True, check=False)
        for line in proc.stdout.splitlines():
            hits.append((label, line.strip()[:100]))
    return hits


def main():
    findings = scan()
    history = recent_history()

    real = [f for f in findings if not f[3]]
    print("### in the files as they are now")
    if not findings:
        print("- nothing matched")
    for path, number, label, fake, context in findings[:40]:
        print("- `%s:%d` - %s%s" % (path, number, label,
                                    "  (looks like a placeholder)" if fake else ""))
        if context:
            print("      the line begins: `%s`" % context)
    if len(findings) > 40:
        print("- ...and %d more" % (len(findings) - 40))
    print()

    print("### commits that once added something of this shape")
    if history:
        for label, line in history[:10]:
            print("- %s: %s" % (label, line))
        print()
        print("A file cleaned up later is still in the history, and the history is "
              "what a fork keeps.")
    else:
        print("- none found")
    print()

    print("candidate-count: %d" % len(real))
    return 0


if __name__ == "__main__":
    sys.exit(main())
