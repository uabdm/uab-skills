#!/usr/bin/env bash
# Zips the generated app so it can be handed to the project leader as a
# single downloadable file. Run from the generated app's repo root.
#
# This is the fast/POC counterpart to uab-app-creator's scripts/
# package-app.sh — deliberately has NO verification gate. This skill never
# runs npm/pip, never installs, audits, builds, or checks the generated
# app in any way (see SKILL.md for why), so there is no .verify/PASSED
# marker to require here. It just archives whatever source files were
# generated. Never use this for real project work — only for the fast,
# explicitly-unverified POC/demo path this skill exists for.
#
# Excludes anything reinstallable or local-only: dependency folders, build
# output, local data fallbacks, and any real secrets in .env.local — none
# of that belongs in a handoff zip. Most of these won't actually exist
# (nothing was ever installed or run), but the exclusions are kept
# defensive in case this code is later run through uab-app-creator's full
# flow, or by hand, before being packaged again. Tries, in order, whatever
# archiving tool is actually available on this machine: zip, PowerShell's
# Compress-Archive (Windows), then Python's stdlib zipfile module. Fails
# with a clear message rather than silently producing an empty or partial
# archive. After packaging, spot-checks the zip's own contents for
# anything that should never have made it in.
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
# it's variable names and comments only, no real values. .verify/ is
# excluded defensively even though this skill never writes it itself.
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

echo "== packaging ${APP_DIR} into ${OUT_ZIP} (fast path — nothing was installed, audited, or built) =="
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
echo "NOTE: this zip is UNVERIFIED — dependencies were never installed, audited, or built. See SKILL.md's report-back step for what to tell the project leader."
