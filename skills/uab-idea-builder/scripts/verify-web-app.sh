#!/usr/bin/env bash
# Mechanical verification for the Next.js layout: install, build, start the
# dev server, and confirm both / and /api/health return 200 with a clean
# log — the equivalent of the old OUTPUT 7 STEPS 1-3. Judgment-based checks
# (reading the generated code back, confirming auth/data-layer wiring) stay
# in references/verification-checklist.md — this script only covers what's
# safe to automate the same way every time.
#
# Run from the generated app's repo root. Always stops the dev server
# before exiting, pass or fail.
set -uo pipefail

PORT="${PORT:-3000}"
LOG_FILE="$(mktemp)"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "== stopping dev server (pid $SERVER_PID) =="
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
node --version >/dev/null 2>&1 || fail "node not found on this machine — see references/git-workflow.md for what to tell the project leader"
npm --version  >/dev/null 2>&1 || fail "npm not found on this machine — see references/git-workflow.md for what to tell the project leader"
echo "node $(node --version), npm $(npm --version)"

echo "== STEP 1: npm install =="
npm install || fail "npm install failed — see the error above"

echo "== STEP 2: npm run build =="
npm run build || fail "npm run build failed — fix the reported errors (missing deps, wrong import paths, type errors are the usual culprits), then re-run this script"

echo "== STEP 3: start dev server =="
npm run dev >"$LOG_FILE" 2>&1 &
SERVER_PID=$!

echo "waiting for http://localhost:$PORT to respond..."
ready=""
for _ in $(seq 1 30); do
  if curl -s -o /dev/null "http://localhost:$PORT/"; then
    ready="yes"
    break
  fi
  sleep 1
done
if [ "$ready" != "yes" ]; then
  echo "---- server log ----"
  cat "$LOG_FILE"
  fail "dev server never became ready within 30s"
fi

echo "== STEP 3: health checks =="
home_status="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/")"
if [ "$home_status" != "200" ]; then
  echo "---- server log ----"; cat "$LOG_FILE"
  fail "GET / returned $home_status, expected 200"
fi
echo "GET / -> 200 OK"

health_status="$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/api/health")"
if [ "$health_status" != "200" ]; then
  echo "---- server log ----"; cat "$LOG_FILE"
  fail "GET /api/health returned $health_status, expected 200"
fi
echo "GET /api/health -> 200 OK"

if grep -qiE 'error|unhandled' "$LOG_FILE"; then
  echo "---- server log contains 'error'/'unhandled' — review before calling this clean ----"
  cat "$LOG_FILE"
fi

echo "PASS: install, build, and both health checks succeeded"
