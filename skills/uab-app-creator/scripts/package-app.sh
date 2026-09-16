#!/usr/bin/env bash
# Zips the generated app so it can be handed to the project leader as a
# single downloadable file. Run from the generated app's repo root, after
# verification (verify-web-app.sh / verify-worker-app.sh) has passed.
#
# Excludes anything reinstallable or local-only: dependency folders, build
# output, local data fallbacks, and any real secrets in .env.local — none of
# that belongs in a handoff zip. Tries, in order, whatever archiving tool is
# actually available on this machine: zip, PowerShell's Compress-Archive
# (Windows), then Python's stdlib zipfile module. Fails with a clear message
# rather than silently producing an empty or partial archive.
set -uo pipefail

fail() {
  echo "FAIL: $1"
  exit 1
}

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
    --exclude='.git' --exclude='.env' --exclude='.env.local' \
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
skip_dirs = {"node_modules", ".next", ".venv", "__pycache__", ".data", ".localstorage", ".git"}
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

echo "PASS: wrote $(pwd)/${OUT_ZIP}"
