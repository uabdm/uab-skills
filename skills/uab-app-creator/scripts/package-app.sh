#!/usr/bin/env bash
# Zips the generated app so it can be handed to the project leader as a
# single downloadable file. Run from the generated app's repo root, after
# verification (verify-web-app.sh / verify-worker-app.sh) has passed.
#
# Refuses to run at all unless .verify/PASSED exists AND its recorded hash
# matches the CURRENT source (see _verify_hash.sh) — this is what makes
# "never package before verification passes" an enforced gate instead of a
# rule a model has to remember and self-report honestly. A fix made after
# the last successful verify run, however small, invalidates the marker
# and blocks packaging until the matching verify script is re-run.
#
# Excludes anything reinstallable or local-only: dependency folders, build
# output, local data fallbacks, the verification marker itself, and any
# real secrets in .env.local — none of that belongs in a handoff zip. Tries,
# in order, whatever archiving tool is actually available on this machine:
# zip, PowerShell's Compress-Archive (Windows), then Python's stdlib
# zipfile module. Fails with a clear message rather than silently producing
# an empty or partial archive. After packaging, spot-checks the zip's own
# contents for anything that should never have made it in.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_verify_hash.sh
source "$SCRIPT_DIR/_verify_hash.sh"

fail() {
  echo "FAIL: $1"
  exit 1
}

echo "== checking verification marker =="
[ -f .verify/PASSED ] || fail "no .verify/PASSED marker found — run scripts/verify-web-app.sh or scripts/verify-worker-app.sh (whichever matches this app) and confirm it passes before packaging"
RECORDED_HASH="$(grep '^hash=' .verify/PASSED | cut -d= -f2)"
CURRENT_HASH="$(compute_source_hash)" || fail "could not compute a verification hash — see the error above"
if [ "$RECORDED_HASH" != "$CURRENT_HASH" ]; then
  fail "source has changed since the last successful verification (recorded hash ${RECORDED_HASH:-<none>}, current $CURRENT_HASH) — re-run the matching verify script before packaging. This is what stops a fix made after verification from shipping unverified."
fi
echo "PASS: verification marker is fresh (verified $(grep '^verified_at=' .verify/PASSED | cut -d= -f2))"

APP_DIR="$(pwd)"
APP_NAME="$(basename "$APP_DIR")"
OUT_ZIP="${APP_NAME}.zip"

# Everything in this list is either reinstallable (node_modules, .venv,
# __pycache__, build output) or must never leave this machine (.env.local
# real secrets, local SQLite/file-storage data). .env.template ships fine —
# it's variable names and comments only, no real values.
EXCLUDES=(
  "node_modules/*" "*/node_modules/*"
  ".next/*" "*/.next/*"
  ".venv/*" "*/.venv/*"
  "__pycache__/*" "*/__pycache__/*"
  ".data/*" "*/.data/*"
  ".localstorage/*" "*/.localstorage/*"
  ".git/*" "*/.git/*"
  ".verify/*" "*/.verify/*"
  ".env" ".env.local" "*/.env" "*/.env.local"
  "${OUT_ZIP}"
)

echo "== packaging ${APP_DIR} into ${OUT_ZIP} =="
rm -f "$OUT_ZIP"

if command -v zip >/dev/null 2>&1; then
  echo "using: zip"
  zip -r -q "$OUT_ZIP" . -x "${EXCLUDES[@]}" || fail "zip failed — see the error above"

elif command -v powershell.exe >/dev/null 2>&1; then
  echo "using: PowerShell Compress-Archive"
  # Compress-Archive has no exclude flag, so stage a filtered copy first.
  STAGE_DIR="$(mktemp -d)/${APP_NAME}"
  mkdir -p "$STAGE_DIR"
  tar -c \
    --exclude='node_modules' --exclude='.next' --exclude='.venv' \
    --exclude='__pycache__' --exclude='.data' --exclude='.localstorage' \
    --exclude='.git' --exclude='.verify' --exclude='.env' --exclude='.env.local' \
    -f - . | tar -x -f - -C "$STAGE_DIR" || fail "staging files for Compress-Archive failed"
  powershell.exe -NoProfile -Command \
    "Compress-Archive -Path '$(cd "$STAGE_DIR" && pwd -W 2>/dev/null || pwd)/*' -DestinationPath '${OUT_ZIP}' -Force" \
    || fail "PowerShell Compress-Archive failed — see the error above"
  rm -rf "$(dirname "$STAGE_DIR")"

elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3 || command -v python)"
  echo "using: python zipfile"
  "$PYTHON_BIN" - "$OUT_ZIP" <<'PYEOF' || fail "python zipfile packaging failed — see the error above"
import os, sys, zipfile

out_zip = sys.argv[1]
skip_dirs = {"node_modules", ".next", ".venv", "__pycache__", ".data", ".localstorage", ".git", ".verify"}
skip_files = {".env", ".env.local", out_zip}

with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as zf:
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in skip_dirs]
        for name in files:
            if name in skip_files:
                continue
            path = os.path.join(root, name)
            zf.write(path, os.path.relpath(path, "."))
print(f"wrote {out_zip}")
PYEOF

else
  fail "no archiving tool found (tried zip, PowerShell Compress-Archive, python zipfile). Install any one of these, or zip the folder by hand, excluding node_modules/.venv/__pycache__/.next/.git/.data/.localstorage/.env/.env.local."
fi

[ -f "$OUT_ZIP" ] || fail "expected ${OUT_ZIP} to exist after packaging but it doesn't"
[ -s "$OUT_ZIP" ] || fail "${OUT_ZIP} exists but is empty"

echo "== spot-checking zip contents =="
ZIP_LISTING=""
if command -v unzip >/dev/null 2>&1; then
  ZIP_LISTING="$(unzip -Z1 "$OUT_ZIP" 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3 || command -v python)"
  ZIP_LISTING="$("$PYTHON_BIN" -c "import zipfile,sys; print('\n'.join(zipfile.ZipFile(sys.argv[1]).namelist()))" "$OUT_ZIP" 2>/dev/null)"
fi

if [ -z "$ZIP_LISTING" ]; then
  echo "WARN: no tool available to list zip contents (tried unzip, python zipfile) — skipping the spot-check, but the exclude list above should have kept these out regardless"
else
  BAD_ENTRIES="$(echo "$ZIP_LISTING" | grep -E '(^|/)(node_modules|\.next|__pycache__|\.venv|\.git|\.verify|\.data|\.localstorage)(/|$)|(^|/)\.env(\.local)?$' || true)"
  if [ -n "$BAD_ENTRIES" ]; then
    echo "$BAD_ENTRIES"
    fail "the zip contains path(s) that should have been excluded (see above) — the archiving tool's exclude flags did not behave as expected on this machine; do not hand off this zip"
  fi
  echo "PASS: zip contains no excluded paths ($(echo "$ZIP_LISTING" | wc -l) files total)"
fi

echo "PASS: wrote $(pwd)/${OUT_ZIP}"
