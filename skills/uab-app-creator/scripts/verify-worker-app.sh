#!/usr/bin/env bash
# Mechanical verification for the Python/FastAPI worker layout: install,
# start uvicorn, and confirm /health returns 200 with a clean log. Also
# runs lint-checklist.sh and, only on a full pass, writes .verify/PASSED —
# see verify-web-app.sh for the Next.js equivalent and the full design
# note on why that marker exists (it's what makes package-app.sh's
# packaging gate enforced rather than a rule the model has to remember).
#
# Run from the generated app's repo root. Always stops uvicorn before
# exiting, pass or fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_verify_hash.sh
source "$SCRIPT_DIR/_verify_hash.sh"

PORT="${PORT:-8000}"
LOG_FILE="$(mktemp)"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "== stopping uvicorn (pid $SERVER_PID) =="
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

fail() {
  echo "FAIL: $1"
  exit 1
}

echo "== STEP 1: runtime check =="
"$SCRIPT_DIR/preflight-check.sh" worker || fail "runtime check failed — see the preflight report above and references/git-workflow.md for what to tell the project leader"

# Pick whichever of python3/python actually runs — checking PATH presence
# alone (`command -v`) isn't enough: on Windows, `python3` (and sometimes
# `python`) can resolve to a non-functional Microsoft Store alias stub that
# exists on PATH but errors out when invoked, while the real interpreter
# sits under a different name. Probe execution, not just presence. (The
# preflight check above already confirmed one of these works — this just
# re-picks the same one for the rest of this script to use.)
PYTHON_BIN=""
for candidate in python3 python; do
  if "$candidate" --version >/dev/null 2>&1; then
    PYTHON_BIN="$candidate"
    break
  fi
done
[ -n "$PYTHON_BIN" ] || fail "python not found on this machine — see references/git-workflow.md for what to tell the project leader"
echo "$("$PYTHON_BIN" --version)"

echo "== STEP 1: pip install -r requirements.txt =="
"$PYTHON_BIN" -m pip install -r requirements.txt || fail "pip install failed — see the error above"

echo "== STEP 3: start uvicorn =="
"$PYTHON_BIN" -m uvicorn app.main:app --host 0.0.0.0 --port "$PORT" >"$LOG_FILE" 2>&1 &
SERVER_PID=$!

echo "waiting for http://localhost:$PORT/health to respond..."
ready=""
for _ in $(seq 1 20); do
  if curl -s -o /dev/null "http://localhost:$PORT/health"; then
    ready="yes"
    break
  fi
  sleep 1
done
if [ "$ready" != "yes" ]; then
  echo "---- server log ----"
  cat "$LOG_FILE"
  fail "uvicorn never became ready within 20s"
fi

health_status="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/health")"
if [ "$health_status" != "200" ]; then
  echo "---- server log ----"; cat "$LOG_FILE"
  fail "GET /health returned $health_status, expected 200"
fi
echo "GET /health -> 200 OK"

if grep -qiE 'error|traceback' "$LOG_FILE"; then
  echo "---- server log contains 'error'/'traceback' — review before calling this clean ----"
  cat "$LOG_FILE"
fi

echo "PASS: install and health check succeeded"

echo "== STEP 4: mechanical checklist (lint-checklist.sh) =="
"$SCRIPT_DIR/lint-checklist.sh" worker || fail "lint-checklist.sh found problems — fix them, then re-run this script. Packaging is blocked until this passes."

echo "== STEP 5: writing verification marker =="
mkdir -p .verify
SOURCE_HASH="$(compute_source_hash)" || fail "could not compute a verification hash — see the error above"
{
  echo "app_type=worker"
  echo "hash=$SOURCE_HASH"
  echo "verified_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > .verify/PASSED
echo "wrote .verify/PASSED (hash $SOURCE_HASH) — scripts/package-app.sh requires this to match the current source before it will zip"
