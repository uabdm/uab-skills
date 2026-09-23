#!/usr/bin/env bash
# Mechanical verification for the Python/FastAPI worker layout: install
# dependencies only. Also runs lint-checklist.sh and, only on a full pass,
# writes .verify/PASSED — see verify-web-app.sh for the Next.js equivalent,
# the full design note on why that marker exists (it's what makes
# package-app.sh's packaging gate enforced rather than a rule the model has
# to remember), and why this deliberately does NOT start uvicorn or curl
# /health: this app's own Dockerfile still runs it for real at actual
# deployment time, and re-running it a second time here, inside a
# throwaway code-generation sandbox, is redundant with that.
#
# Run from the generated app's repo root.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_verify_hash.sh
source "$SCRIPT_DIR/_verify_hash.sh"

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
echo "PASS: pip install succeeded"

echo "== STEP 2: mechanical checklist (lint-checklist.sh) =="
"$SCRIPT_DIR/lint-checklist.sh" worker || fail "lint-checklist.sh found problems — fix them, then re-run this script. Packaging is blocked until this passes."

echo "== STEP 3: writing verification marker =="
mkdir -p .verify
SOURCE_HASH="$(compute_source_hash)" || fail "could not compute a verification hash — see the error above"
{
  echo "app_type=worker"
  echo "hash=$SOURCE_HASH"
  echo "verified_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > .verify/PASSED
echo "wrote .verify/PASSED (hash $SOURCE_HASH) — scripts/package-app.sh requires this to match the current source before it will zip"
