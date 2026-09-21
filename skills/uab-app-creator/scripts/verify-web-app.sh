#!/usr/bin/env bash
# Mechanical verification for the Next.js layout: install, build, start the
# dev server, and confirm both / and /api/health return 200 with a clean
# log — the equivalent of the old OUTPUT 7 STEPS 1-3. Also runs
# lint-checklist.sh (the mechanized subset of verification-checklist.md)
# and, only if every one of those passes, writes .verify/PASSED — a marker
# package-app.sh refuses to package without. That marker is what makes
# "never tell the project leader the app is ready before this passes" an
# enforced gate instead of a rule the model has to remember and self-report
# honestly across many separate tool calls. Judgment-based checks that
# can't be scripted (visual layout, the generation manifest) stay in
# references/verification-checklist.md.
#
# Run from the generated app's repo root. Always stops the dev server
# before exiting, pass or fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_verify_hash.sh
source "$SCRIPT_DIR/_verify_hash.sh"

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
"$SCRIPT_DIR/preflight-check.sh" web || fail "runtime check failed — see the preflight report above and references/git-workflow.md for what to tell the project leader"

echo "== STEP 1: npm install =="
npm install || fail "npm install failed — see the error above"

echo "== STEP 1: npm audit =="
# Auto-apply non-breaking fixes first (never --force here — a breaking bump
# can reintroduce a different peer conflict; that needs a human/agent
# decision, not a silent version jump).
npm audit fix >/dev/null 2>&1 || true
if ! npm audit --audit-level=high; then
  fail "npm audit found high/critical vulnerabilities that npm audit fix couldn't resolve automatically — run 'npm audit' for details, upgrade the flagged package (or whatever pulls it in) to a patched version, then re-run this script. Never use 'npm audit fix --force' without checking the changelog for breaking changes first."
fi
echo "PASS: no high/critical vulnerabilities remain"

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

echo "== STEP 4: mechanical checklist (lint-checklist.sh) =="
"$SCRIPT_DIR/lint-checklist.sh" web || fail "lint-checklist.sh found problems — fix them, then re-run this script. Packaging is blocked until this passes."

echo "== STEP 5: writing verification marker =="
mkdir -p .verify
SOURCE_HASH="$(compute_source_hash)" || fail "could not compute a verification hash — see the error above"
{
  echo "app_type=web"
  echo "hash=$SOURCE_HASH"
  echo "verified_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > .verify/PASSED
echo "wrote .verify/PASSED (hash $SOURCE_HASH) — scripts/package-app.sh requires this to match the current source before it will zip"
