#!/usr/bin/env bash
# Packages the app for handoff to another environment (a download, or a
# different repo/sandbox) when this one can't finish every QA phase — most
# commonly because a build or dev-server start keeps hitting the sandbox's
# timeout even when backgrounded. See references/timeout-fallback.md for
# when this is the right move.
#
# Ships whatever WAS completed in the working tree as-is — most importantly
# Phase 1's installed/audited dependency files (package.json/
# package-lock.json, or requirements.txt) reflect any npm-audit fixes
# already applied, so those travel with the handoff even if later phases
# never ran.
#
# Excludes node_modules/.venv and build output (.next/dist/build) — large,
# fully regenerable in the receiving environment via `npm install`/
# `pip install` and a rebuild, and excluding them keeps the zip itself from
# ballooning or becoming its own timeout risk while compressing gigabytes of
# installed packages. Excludes .git (history not needed for a handoff) and
# .qa/ (this skill's own scratch state — the smoke-test spec, bg job logs —
# not part of the shipped app).
#
# Usage: scripts/package-for-handoff.sh [output-path]
#   Defaults to ../<dirname>-qa-handoff-<timestamp>.zip — deliberately
#   OUTSIDE the app directory so the archive doesn't try to include itself.
# Run from the app's repo root.
set -uo pipefail

fail() { echo "FAIL: $1" >&2; exit 1; }

OUT="${1:-}"
APP_DIR="$(pwd)"
APP_NAME="$(basename "$APP_DIR")"
TS="$(date +%Y%m%d-%H%M%S)"
[ -n "$OUT" ] || OUT="../${APP_NAME}-qa-handoff-${TS}.zip"

if command -v zip >/dev/null 2>&1; then
  (
    cd .. || exit 1
    zip -rq "$OUT" "$APP_NAME" \
      -x "$APP_NAME/node_modules/*" \
      -x "$APP_NAME/.git/*" \
      -x "$APP_NAME/.next/*" \
      -x "$APP_NAME/.qa/*" \
      -x "$APP_NAME/dist/*" \
      -x "$APP_NAME/build/*" \
      -x "$APP_NAME/.venv/*" \
      -x "$APP_NAME/*/__pycache__/*" \
      -x "$APP_NAME/__pycache__/*"
  ) || fail "'zip' command failed"
elif command -v tar >/dev/null 2>&1; then
  OUT="${OUT%.zip}.tar.gz"
  (
    cd .. || exit 1
    tar \
      --exclude="$APP_NAME/node_modules" \
      --exclude="$APP_NAME/.git" \
      --exclude="$APP_NAME/.next" \
      --exclude="$APP_NAME/.qa" \
      --exclude="$APP_NAME/dist" \
      --exclude="$APP_NAME/build" \
      --exclude="$APP_NAME/.venv" \
      --exclude="__pycache__" \
      -czf "$OUT" "$APP_NAME"
  ) || fail "'tar' command failed"
else
  fail "neither 'zip' nor 'tar' is available in this sandbox. Run scripts/check-and-install-tools.sh first (see references/environment-preflight.md); if it still can't install either one, there is no way to produce a downloadable archive here — say so explicitly rather than skipping packaging silently, since this zip may be the only deliverable this environment can produce."
fi

[ -f "$OUT" ] || fail "expected output '$OUT' was not created"

SIZE="$(du -h "$OUT" 2>/dev/null | cut -f1)"
echo "PASS: packaged app to $OUT ($SIZE)"
echo "Excludes node_modules/.venv and build output (.next/dist/build) — the receiving environment"
echo "must run 'npm install' (or 'pip install -r requirements.txt') before building or starting it."
echo "package.json/package-lock.json (or requirements.txt) are included exactly as Phase 1 left them,"
echo "so any npm-audit fixes already applied travel with this handoff."
