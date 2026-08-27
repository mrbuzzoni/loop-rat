#!/usr/bin/env bash
# act.sh - the actual work for the pr-hunter loop.
#
# Facts are gathered by shell, judgment is asked of the model. Keep it that way:
# anything a script can determine should never cost a token, and anything a
# script determined can be checked later without rerunning the shift.
set -uo pipefail

FACTS="$RAT_RECEIPT/facts.md"

{
  echo "### repository"
  echo "branch: $(git -C "$RAT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'not a git repo')"
  echo "head:   $(git -C "$RAT_ROOT" log -1 --pretty='%h %s (%cr)' 2>/dev/null || echo '-')"
  echo

  echo "### open pull requests"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh pr list --state open --limit 25 \
       --json number,title,createdAt,updatedAt,isDraft,author,statusCheckRollup,reviewDecision \
       --template '{{range .}}#{{.number}} {{.title}}
  author: {{.author.login}}  draft: {{.isDraft}}  review: {{.reviewDecision}}
  opened: {{timeago .createdAt}}  last activity: {{timeago .updatedAt}}
  checks: {{range .statusCheckRollup}}{{.conclusion}} {{end}}
{{end}}' 2>/dev/null || echo "(gh failed - see stderr)"
  else
    echo "(gh is not installed or not authenticated - falling back to local branches)"
    echo
    git -C "$RAT_ROOT" for-each-ref --sort=-committerdate refs/heads/ \
      --format='%(refname:short) - %(committerdate:relative) - %(contents:subject)' 2>/dev/null | head -n 25
  fi
  echo

  echo "### what the last shift saw"
  if [ -f "$RAT_ROOT/state/checkpoint.json" ]; then
    python3 "$RAT_ROOT/bin/lib/conf.py" get "$RAT_ROOT/state/checkpoint.json" "loops.pr-hunter.cursor" 2>/dev/null \
      || echo "(no cursor yet - this is the first shift)"
  else
    echo "(no checkpoint yet - this is the first shift)"
  fi
} > "$FACTS"

{
  cat "$RAT_RECEIPT/prompt.md"
  echo
  echo "## The facts, collected before you woke up"
  echo
  cat "$FACTS"
} | rat-agent --tag act
