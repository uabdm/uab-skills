#!/usr/bin/env bash
# Runs a command fully detached from the invoking shell/tool call, so a
# sandboxed agent harness's per-command wall-clock timeout (confirmed to
# exist on TrueForge's Daytona-backed sandbox — a cold `npm run build` can
# exceed it easily) can never kill legitimate long-running work. This
# call itself returns almost instantly regardless of how long the wrapped
# command takes; poll the result with scripts/bg-status.sh in separate,
# cheap, near-instant tool calls instead of blocking on one big call.
#
# Usage: scripts/bg-run.sh <label> <command...>
#   scripts/bg-run.sh build npm run build
#   scripts/bg-run.sh verify bash scripts/verify-web-app.sh
#
# State lives under .verify/bg/<label>.{log,pid,exit} — .verify/ is
# already excluded from git/docker/the handoff zip everywhere else in
# this skill, so nothing extra is needed to keep this out of those.
set -uo pipefail

LABEL="${1:?usage: scripts/bg-run.sh <label> <command...>}"
shift
[ "$#" -gt 0 ] || { echo "FAIL: no command given to run" >&2; exit 1; }

BG_DIR=".verify/bg"
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
if command -v setsid >/dev/null 2>&1; then
  setsid bash -c '"$@" >"$LOG" 2>&1; echo $? > "$EXIT_FILE"' _ "$@" </dev/null &
else
  nohup bash -c '"$@" >"$LOG" 2>&1; echo $? > "$EXIT_FILE"' _ "$@" </dev/null &
  disown
fi
BG_PID=$!
echo "$BG_PID" > "$PID_FILE"

echo "started '$LABEL' in the background (pid $BG_PID)"
echo "poll it with: scripts/bg-status.sh $LABEL"
