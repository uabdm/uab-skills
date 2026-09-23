#!/usr/bin/env bash
# Runs a command fully detached from the invoking shell/tool call, so a
# sandboxed agent harness's per-command wall-clock timeout (confirmed to
# exist on TrueForge's Daytona-backed sandbox — a cold `npm run build` can
# exceed it easily) can never kill legitimate long-running work. This
# call itself returns almost instantly regardless of how long the wrapped
# command takes; poll the result with scripts/bg-status.sh in separate,
# cheap, near-instant tool calls instead of blocking on one big call.
#
# Copied from uab-app-creator/scripts/bg-run.sh (same mechanism, same
# rationale) — kept as its own copy here so this skill stays self-
# contained and doesn't depend on a sibling skill's folder existing on
# disk next to it.
#
# Usage: scripts/bg-run.sh <label> <command...>
#   scripts/bg-run.sh install npm install
#   scripts/bg-run.sh build npm run build
#
# Do NOT wrap the trailing command in quotes as a single string — pass it
# as separate words exactly as you'd type it directly on a command line.
#   RIGHT: scripts/bg-run.sh build npm run build
#   WRONG: scripts/bg-run.sh build "npm run build"   (fails with
#          "npm run build: command not found" — the whole phrase gets
#          treated as one literal program name instead of three words)
#
# State lives under .qa/bg/<label>.{log,pid,exit} — add .qa/ to the app's
# .gitignore alongside its usual node_modules/.next entries.
set -uo pipefail

LABEL="${1:?usage: scripts/bg-run.sh <label> <command...> -- pass the command as separate words, NOT one quoted string (see the header comment above)}"
shift
[ "$#" -gt 0 ] || { echo "FAIL: no command given to run" >&2; exit 1; }
if [ "$#" -eq 1 ] && [[ "$1" == *' '* ]]; then
  echo "WARN: the command looks like a single quoted string ('$1') containing spaces, not separate words." >&2
  echo "      This will almost certainly fail with '<the whole string>: command not found'." >&2
  echo "      Re-run as separate words instead, e.g.: scripts/bg-run.sh $LABEL $1" >&2
fi

BG_DIR=".qa/bg"
mkdir -p "$BG_DIR"
LOG="$BG_DIR/$LABEL.log"
PID_FILE="$BG_DIR/$LABEL.pid"
EXIT_FILE="$BG_DIR/$LABEL.exit"
rm -f "$EXIT_FILE"
: > "$LOG"

export LOG EXIT_FILE

# setsid fully detaches into a new session — no controlling terminal, and
# critically not part of the invoking shell's process GROUP. That matters
# because some sandbox harnesses kill an entire process group when a
# timed-out command is torn down, which a plain `&`/`nohup` job (same
# group) would die alongside. setsid survives that; nohup+disown is the
# fallback where setsid isn't installed (still survives the parent shell
# simply exiting, just not a hard group-kill).
#
# The `>/dev/null 2>&1` on THIS launch line (separate from the `>"$LOG"
# 2>&1` inside the script string, which redirects the wrapped command's
# own output) is not optional. Without it, this outer bash -c process
# inherits stdout/stderr from whatever pipe the calling tool harness is
# reading. Many such harnesses treat a command as "finished" only once
# that pipe reaches EOF, which requires EVERY process holding a copy of
# that fd to close it, not just the top-level process this script
# launches. A detached child that still holds an inherited (even unused)
# copy of that fd keeps the pipe open — and therefore the ORIGINAL tool
# call blocked — for as long as the detached command itself runs,
# completely defeating the point of backgrounding it. This is invisible on
# a fast command (the leaked fd closes within milliseconds) and only bites
# on a slow one — exactly the "a trivial echo test passes, the real
# multi-minute npm command still times out" pattern this fixes.
if command -v setsid >/dev/null 2>&1; then
  setsid bash -c '"$@" >"$LOG" 2>&1; echo $? > "$EXIT_FILE"' _ "$@" </dev/null >/dev/null 2>&1 &
else
  nohup bash -c '"$@" >"$LOG" 2>&1; echo $? > "$EXIT_FILE"' _ "$@" </dev/null >/dev/null 2>&1 &
  disown
fi
BG_PID=$!
echo "$BG_PID" > "$PID_FILE"

echo "started '$LABEL' in the background (pid $BG_PID)"
echo "poll it with: scripts/bg-status.sh $LABEL"
