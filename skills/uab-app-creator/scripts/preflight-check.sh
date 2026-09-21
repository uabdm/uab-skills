#!/usr/bin/env bash
# Confirms this sandbox/machine can actually run the rest of the skill
# BEFORE any app files are generated. Written for sandboxes (e.g. a
# Daytona workspace launched inside TrueForge) that sometimes boot with
# Node/npm installed but not actually usable in the shell this script runs
# in — a different failure than "not installed at all", and one that's
# cheap to detect and often cheap to self-heal, so this script tries both
# before giving up.
#
# Usage: scripts/preflight-check.sh web|worker
#
# Exit 0 = safe to proceed with generation. Exit 1 = do not generate the
# app yet; the printed report says exactly what's missing and, for a
# genuinely broken sandbox, gives you something concrete to hand to
# whoever maintains the TrueForge/Daytona image.
set -uo pipefail

APP_TYPE="${1:-}"
if [ "$APP_TYPE" != "web" ] && [ "$APP_TYPE" != "worker" ]; then
  echo "FAIL: usage: scripts/preflight-check.sh web|worker" >&2
  exit 1
fi

PROBLEMS=()
note()  { echo "-- $1"; }
warn()  { echo "WARN: $1"; }
add_problem() { PROBLEMS+=("$1"); }

# ---------------------------------------------------------------------------
# Self-heal pass: if a runtime isn't resolving, this is frequently a PATH
# problem specific to how the sandbox shell was started (a non-login/
# non-interactive shell never sourced nvm/volta/fnm's init script) rather
# than the runtime being absent. Try the common install locations before
# concluding it's actually missing. This only patches PATH for the
# lifetime of THIS script — it deliberately does not edit any shell rc
# file (same "don't half-fix a machine you don't own" stance as
# references/git-workflow.md).
heal_path() {
  local candidates=(
    "$HOME/.nvm/current/bin"
    "$HOME/.volta/bin"
    "$HOME/.fnm"
    "$HOME/.local/bin"
    "/usr/local/bin"
    "/opt/homebrew/bin"
  )
  # nvm keeps versions under versions/node/<version>/bin rather than a
  # stable path — glob for whatever's actually installed.
  if [ -d "$HOME/.nvm/versions/node" ]; then
    for d in "$HOME"/.nvm/versions/node/*/bin; do
      [ -d "$d" ] && candidates+=("$d")
    done
  fi
  for d in "${candidates[@]}"; do
    case ":$PATH:" in
      *":$d:"*) ;;
      *) [ -d "$d" ] && PATH="$d:$PATH" ;;
    esac
  done
  export PATH
  # nvm/fnm also expose themselves as shell functions via an init script,
  # not just a PATH entry — source it if present so `nvm`/`fnm` resolve too
  # in case a later step wants a specific version.
  [ -s "$HOME/.nvm/nvm.sh" ] && \. "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true
}
heal_path

echo "== preflight: $APP_TYPE app =="
note "PATH=$PATH"

# ---------------------------------------------------------------------------
# Probe EXECUTION, not just PATH presence — on some sandboxes a binary
# resolves on PATH but errors out when actually invoked (a stub, a broken
# symlink, a shim pointing at a runtime that was never fully installed).
probe() {
  local bin="$1"
  shift
  if "$bin" "$@" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

if [ "$APP_TYPE" = "web" ]; then
  if ! command -v node >/dev/null 2>&1 || ! probe node --version; then
    add_problem "node did not resolve or did not run (tried: $(command -v node 2>/dev/null || echo 'not on PATH'))"
  else
    NODE_VERSION="$(node --version)"
    note "node $NODE_VERSION at $(command -v node)"
    NODE_MAJOR="$(echo "$NODE_VERSION" | sed -E 's/^v([0-9]+).*/\1/')"
    if [ -n "$NODE_MAJOR" ] && [ "$NODE_MAJOR" -lt 22 ] 2>/dev/null; then
      add_problem "node is $NODE_VERSION but this skill's generated apps require Node >= 22 (data-layer.md's node:sqlite storage needs it) — sandbox image needs a newer Node"
    fi
  fi

  if ! command -v npm >/dev/null 2>&1 || ! probe npm --version; then
    add_problem "npm did not resolve or did not run (tried: $(command -v npm 2>/dev/null || echo 'not on PATH')) — npm install/npm audit cannot run without it"
  else
    note "npm $(npm --version) at $(command -v npm)"
  fi

  if ! command -v npx >/dev/null 2>&1 || ! probe npx --version; then
    warn "npx did not resolve — not required by this skill's scripts today, but note it if present in the report"
  fi

  # A binary that resolves and runs can still fail every install because
  # the sandbox has no route to the registry (egress allowlist, proxy not
  # configured, DNS). This is a different fix (network/platform config)
  # than "install node", so it needs to be reported as its own problem
  # rather than surfacing 60 seconds later as a confusing npm install
  # timeout.
  if command -v npm >/dev/null 2>&1; then
    REGISTRY="$(npm config get registry 2>/dev/null || echo 'https://registry.npmjs.org/')"
    if command -v curl >/dev/null 2>&1; then
      if ! curl -s -o /dev/null -m 8 --fail "$REGISTRY"; then
        add_problem "npm's configured registry ($REGISTRY) is unreachable from this sandbox within 8s — this is a network/egress problem, not a missing-tool problem; npm install will hang or fail even though npm itself works"
      else
        note "npm registry reachable: $REGISTRY"
      fi
    fi
  fi
else
  PYTHON_BIN=""
  for candidate in python3 python; do
    if probe "$candidate" --version; then
      PYTHON_BIN="$candidate"
      break
    fi
  done
  if [ -z "$PYTHON_BIN" ]; then
    add_problem "neither python3 nor python resolved and ran (checked both — see verify-worker-app.sh's note on Windows Store alias stubs)"
  else
    note "$("$PYTHON_BIN" --version) at $(command -v "$PYTHON_BIN")"
    if ! "$PYTHON_BIN" -m pip --version >/dev/null 2>&1; then
      add_problem "pip did not run under $PYTHON_BIN — pip install cannot run without it"
    else
      note "$("$PYTHON_BIN" -m pip --version)"
    fi
    if command -v curl >/dev/null 2>&1; then
      if ! curl -s -o /dev/null -m 8 --fail "https://pypi.org/simple/"; then
        add_problem "PyPI (pypi.org) is unreachable from this sandbox within 8s — this is a network/egress problem, not a missing-tool problem; pip install will hang or fail even though python/pip themselves work"
      else
        note "PyPI reachable"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Shared, both app types.
if ! command -v curl >/dev/null 2>&1; then
  add_problem "curl not found — verify-web-app.sh/verify-worker-app.sh need it for health checks"
fi
if ! command -v zip >/dev/null 2>&1 && ! command -v powershell.exe >/dev/null 2>&1 \
   && { ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; }; then
  warn "no archiving tool found yet (zip / PowerShell / python) — package-app.sh needs one of these, but this only matters at packaging time, not now"
fi

echo "== preflight result =="
if [ "${#PROBLEMS[@]}" -eq 0 ]; then
  echo "PASS: this sandbox can run the $APP_TYPE verify/build/install steps"
  exit 0
fi

echo "FAIL: this sandbox is missing something the $APP_TYPE app needs before generation is worth starting:"
for p in "${PROBLEMS[@]}"; do
  echo "  - $p"
done
echo
echo "Do not generate the app yet. See references/git-workflow.md for what to"
echo "tell the project leader. If node/npm (or python/pip) resolve fine in an"
echo "interactive shell on this same sandbox but failed here, this is very"
echo "likely a non-interactive-shell PATH/init problem specific to how the"
echo "sandbox was launched (common on Daytona-style ephemeral workspaces) —"
echo "report the exact list above to whoever maintains that sandbox image,"
echo "including the PATH line printed at the top of this report."
exit 1
