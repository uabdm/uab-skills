#!/usr/bin/env bash
# Phase 1 of uab-app-qa: install dependencies and resolve npm audit
# findings. Self-contained on purpose — this skill must work whether the
# target app already had `uab-app-creator`'s verify-web-app.sh run against
# it (already installed/audited) or came from uab-app-creator-nobrand/-fast
# or a cold zip (never installed at all). Safe to re-run; `npm install` and
# `npm audit` are both idempotent.
#
# Deliberately does NOT run `npm run build` or start a dev server — that's
# Phase 2/3, in references/build-and-fix.md and
# references/functional-smoke-test.md respectively. Keeping this phase to
# install+audit only means a failure here is unambiguously a dependency
# problem, not tangled up with a compile or runtime error.
#
# Run from the target app's repo root.
set -uo pipefail

fail() {
  echo "FAIL: $1"
  exit 1
}

command -v npm >/dev/null 2>&1 || fail "npm not found in this sandbox — run scripts/check-and-install-tools.sh first (see references/environment-preflight.md) before retrying this script"

echo "== npm install =="
npm install || fail "npm install failed — see references/dependency-audit.md for common causes (peer dependency conflicts, lockfile drift, engines mismatch) before reaching for --legacy-peer-deps or --force"

echo "== npm audit fix (non-breaking) =="
npm audit fix >/dev/null 2>&1 || true

echo "== npm audit (fail on high/critical) =="
if ! npm audit --audit-level=high; then
  fail "npm audit found high/critical vulnerabilities npm audit fix couldn't resolve automatically — see references/dependency-audit.md. Never use 'npm audit fix --force' without reading the advisory/changelog for breaking changes first, and re-run Phase 2 (build) immediately after any forced bump to catch anything it broke."
fi

echo "PASS: install clean, no unresolved high/critical vulnerabilities"
