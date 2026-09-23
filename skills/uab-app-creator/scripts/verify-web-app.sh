#!/usr/bin/env bash
# Mechanical verification for the Next.js layout: install and audit
# dependencies only. Also runs lint-checklist.sh (the mechanized subset of
# verification-checklist.md) and, only if every one of those passes, writes
# .verify/PASSED — a marker package-app.sh refuses to package without. That
# marker is what makes "never tell the project leader the app is ready
# before this passes" an enforced gate instead of a rule the model has to
# remember and self-report honestly across many separate tool calls.
# Judgment-based checks that can't be scripted (visual layout, the
# generation manifest) stay in references/verification-checklist.md.
#
# Deliberately does NOT run `npm run build`, start a dev server, or curl
# any route. This app's own Dockerfile still builds it for real when it's
# actually deployed (Kubernetes or otherwise) — re-building and smoke-
# testing it a second time here, inside a throwaway code-generation
# sandbox, is redundant with that and is what was timing out ephemeral
# sandboxes (confirmed on TrueForge's Daytona-backed sandbox: a cold
# `npm run build` or a long-lived dev-server+curl loop can exceed the
# harness's own per-command wall-clock limit). See SKILL.md's Verify step.
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

echo "== STEP 2: mechanical checklist (lint-checklist.sh) =="
"$SCRIPT_DIR/lint-checklist.sh" web || fail "lint-checklist.sh found problems — fix them, then re-run this script. Packaging is blocked until this passes."

echo "== STEP 3: writing verification marker =="
mkdir -p .verify
SOURCE_HASH="$(compute_source_hash)" || fail "could not compute a verification hash — see the error above"
{
  echo "app_type=web"
  echo "hash=$SOURCE_HASH"
  echo "verified_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > .verify/PASSED
echo "wrote .verify/PASSED (hash $SOURCE_HASH) — scripts/package-app.sh requires this to match the current source before it will zip"
