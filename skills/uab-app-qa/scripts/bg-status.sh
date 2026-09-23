#!/usr/bin/env bash
# Cheap, near-instant status check for a job started with scripts/bg-run.sh.
# Call this repeatedly (a few seconds apart, as separate tool calls) instead
# of blocking on the original long-running command — every call to THIS
# script returns immediately even while the underlying work is still going.
#
# Copied from uab-app-creator/scripts/bg-status.sh — see bg-run.sh's header
# for why this skill keeps its own copy instead of a relative path into a
# sibling skill's folder.
#
# Usage: scripts/bg-status.sh <label>
#
# Exit 0, prints "RUNNING (pid ...)"   — still going, not done yet.
# Exit 0, prints "DONE exit=0"         — finished successfully.
# Exit 1, prints "DONE exit=<n>"       — finished with a non-zero exit code.
# Exit 2, prints "UNKNOWN: no such..." — this label was never started.
# Either way, prints the last 40 lines of the job's log first.
set -uo pipefail

LABEL="${1:?usage: scripts/bg-status.sh <label>}"
BG_DIR=".qa/bg"
LOG="$BG_DIR/$LABEL.log"
PID_FILE="$BG_DIR/$LABEL.pid"
EXIT_FILE="$BG_DIR/$LABEL.exit"

if [ ! -f "$PID_FILE" ]; then
  echo "UNKNOWN: no background job named '$LABEL' was ever started with scripts/bg-run.sh"
  exit 2
fi

echo "---- last 40 lines of $LOG ----"
if [ -f "$LOG" ]; then tail -n 40 "$LOG"; else echo "(no output yet)"; fi
echo "--------------------------------"

if [ -f "$EXIT_FILE" ]; then
  CODE="$(cat "$EXIT_FILE")"
  if [ "$CODE" = "0" ]; then
    echo "DONE exit=0"
    exit 0
  else
    echo "DONE exit=$CODE"
    exit 1
  fi
fi

PID="$(cat "$PID_FILE" 2>/dev/null || echo '')"
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  echo "RUNNING (pid $PID) — not done yet, check again shortly"
  exit 0
else
  echo "UNKNOWN: process isn't running and no exit code was recorded — it may have been killed externally; check the log above"
  exit 3
fi
