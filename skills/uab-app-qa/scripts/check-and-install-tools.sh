#!/usr/bin/env bash
# Phase 0 of uab-app-qa: confirm this sandbox actually has the tools the
# rest of this skill needs before Phase 1 spends effort on a command that's
# about to fail with "command not found" — then make a best-effort attempt
# to install anything missing rather than giving up immediately. See
# references/environment-preflight.md for the full rationale and what a
# failure here means for the phases after it.
#
# Usage: scripts/check-and-install-tools.sh [web|worker]
#   Auto-detects from package.json / requirements.txt|pyproject.toml in the
#   current directory if the app type isn't given explicitly.
#
# Exit 0: every required tool is present (already, or installed just now).
# Exit 1: at least one required tool is missing and couldn't be installed —
#         read references/environment-preflight.md and
#         references/timeout-fallback.md before deciding how to proceed.
set -uo pipefail

APP_TYPE="${1:-}"
if [ -z "$APP_TYPE" ]; then
  if [ -f package.json ]; then
    APP_TYPE="web"
  elif [ -f requirements.txt ] || [ -f pyproject.toml ]; then
    APP_TYPE="worker"
  else
    echo "FAIL: couldn't auto-detect app type — no package.json, requirements.txt, or pyproject.toml in $(pwd)."
    echo "      Pass it explicitly: scripts/check-and-install-tools.sh web   (or 'worker')"
    exit 1
  fi
fi

have() { command -v "$1" >/dev/null 2>&1; }

# Tries each package manager that's actually present, sudo first (most
# sandboxes that have sudo need it), then without (some sandboxes run as
# root already and don't have sudo installed at all). Returns non-zero only
# if no supported package manager exists or every attempt failed.
pkg_install() {
  local pkgs=("$@")
  if have apt-get; then
    { sudo -n apt-get update -y && sudo -n apt-get install -y "${pkgs[@]}"; } 2>/dev/null \
      || { apt-get update -y && apt-get install -y "${pkgs[@]}"; } 2>/dev/null
  elif have apk; then
    sudo -n apk add --no-cache "${pkgs[@]}" 2>/dev/null \
      || apk add --no-cache "${pkgs[@]}" 2>/dev/null
  elif have dnf; then
    sudo -n dnf install -y "${pkgs[@]}" 2>/dev/null \
      || dnf install -y "${pkgs[@]}" 2>/dev/null
  elif have yum; then
    sudo -n yum install -y "${pkgs[@]}" 2>/dev/null \
      || yum install -y "${pkgs[@]}" 2>/dev/null
  elif have brew; then
    brew install "${pkgs[@]}" 2>/dev/null
  else
    return 1
  fi
}

MISSING=()
REPORT=()

check_tool() {
  local tool="$1"; shift
  local install_pkgs=("$@")
  if have "$tool"; then
    REPORT+=("OK: $tool ($("$tool" --version 2>&1 | head -n1))")
    return 0
  fi
  echo "-- '$tool' not found, attempting install (package(s): ${install_pkgs[*]}) --"
  if pkg_install "${install_pkgs[@]}" && have "$tool"; then
    REPORT+=("OK: $tool (installed just now: $("$tool" --version 2>&1 | head -n1))")
  else
    REPORT+=("MISSING: $tool (could not install automatically)")
    MISSING+=("$tool")
  fi
}

case "$APP_TYPE" in
  web)
    check_tool node nodejs
    check_tool npm npm
    ;;
  worker)
    check_tool python3 python3
    check_tool pip3 python3-pip
    ;;
  *)
    echo "FAIL: unknown app type '$APP_TYPE' (expected 'web' or 'worker')"
    exit 1
    ;;
esac

# Needed later if this run ends up packaging a handoff artifact (see
# references/timeout-fallback.md) — check now, while we know what package
# manager access looks like, rather than discovering it's missing mid-fallback.
if ! have zip && ! have tar; then
  echo "-- neither 'zip' nor 'tar' found (needed later for scripts/package-for-handoff.sh), attempting to install 'zip' --"
  pkg_install zip >/dev/null 2>&1 || true
  if have zip; then
    REPORT+=("OK: zip (installed just now)")
  elif have tar; then
    REPORT+=("OK: tar (already present, zip unavailable — package-for-handoff.sh will fall back to .tar.gz)")
  else
    REPORT+=("MISSING: zip/tar (packaging a handoff archive won't be possible in this sandbox)")
  fi
fi

echo "== tool check summary (app type: $APP_TYPE) =="
for line in "${REPORT[@]}"; do echo "$line"; done

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo ""
  echo "FAIL: missing required tool(s) that couldn't be installed automatically: ${MISSING[*]}"
  echo "This sandbox likely lacks package-manager access (no sudo, no network egress to a package"
  echo "registry, or an unsupported base image). See references/environment-preflight.md for what"
  echo "this means for the phases that need it, and references/timeout-fallback.md for packaging"
  echo "whatever can still be delivered instead of stalling here."
  exit 1
fi

echo ""
echo "PASS: all required tools present for a '$APP_TYPE' app"
