#!/usr/bin/env bash
# Confirms this sandbox/machine can actually run the rest of the skill
# BEFORE any app files are generated. Written for sandboxes (e.g. a
# Daytona workspace launched inside TrueForge) that sometimes boot without
# a usable Node/npm — either genuinely absent, or present somewhere this
# shell doesn't see. In an EPHEMERAL AUTOMATION SANDBOX (detected below,
# never on what looks like a human's own machine) this script will attempt
# a real, from-scratch install of Node.js from its own official binary
# release before giving up — there is no human present in that pipeline to
# act on "please install Node.js yourself", so failing loudly accomplishes
# nothing there the way it does when a project leader is at the keyboard.
#
# Usage: scripts/preflight-check.sh web|worker
#
# Exit 0 = safe to proceed with generation. Exit 1 = do not generate the
# app yet; the printed report says exactly what's missing and, for a
# genuinely broken sandbox, gives you something concrete to hand to
# whoever maintains the TrueForge/Daytona image.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_verify_hash.sh
source "$SCRIPT_DIR/_verify_hash.sh"   # reuses _sha256_tool for the download checksum below

APP_TYPE="${1:-}"
if [ "$APP_TYPE" != "web" ] && [ "$APP_TYPE" != "worker" ]; then
  echo "FAIL: usage: scripts/preflight-check.sh web|worker" >&2
  exit 1
fi

PROBLEMS=()
INSTALLED=()
note()  { echo "-- $1"; }
warn()  { echo "WARN: $1"; }
add_problem() { PROBLEMS+=("$1"); }

# ---------------------------------------------------------------------------
# Probe EXECUTION, not just PATH presence — on some sandboxes a binary
# resolves on PATH but errors out when actually invoked (a stub, a broken
# symlink, a shim pointing at a runtime that was never fully installed).
probe() {
  local bin="$1"
  shift
  "$bin" "$@" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Sandbox detection. Every heuristic below is OR'd — any one is enough.
# This deliberately stays conservative (container/CI markers, not "no
# Node found") because everything gated behind it (self-install below)
# must NEVER fire against a project leader's own laptop. If none of these
# match your platform, force it with UAB_FORCE_SANDBOX=1 — and tell
# whoever maintains this skill what env var your platform actually sets so
# the heuristic can be extended (see git-workflow.md).
is_ephemeral_sandbox() {
  [ "${UAB_SKIP_SANDBOX_DETECT:-0}" = "1" ] && return 1
  [ "${UAB_FORCE_SANDBOX:-0}" = "1" ] && return 0
  env | grep -qiE '^(DAYTONA|CODESPACE|GITPOD|CODESANDBOX|E2B)_' && return 0
  [ -f /.dockerenv ] && return 0
  grep -qE 'docker|containerd|kubepods' /proc/1/cgroup 2>/dev/null && return 0
  return 1
}

SANDBOX_DETECTED=0
if is_ephemeral_sandbox; then
  SANDBOX_DETECTED=1
fi

echo "== preflight: $APP_TYPE app =="
note "PATH=$PATH"
if [ "$SANDBOX_DETECTED" = "1" ]; then
  note "ephemeral automation sandbox detected — self-install fallback is allowed here (override with UAB_SKIP_SANDBOX_DETECT=1)"
else
  note "no sandbox markers detected — treating this as a machine a human owns; will report problems instead of installing anything (override with UAB_FORCE_SANDBOX=1)"
fi

# ---------------------------------------------------------------------------
# Makes a resolved binary visible to every FUTURE shell process, not just
# this one. This matters because most agent harnesses run each shell
# command in a brand-new process with no inherited env — an `export PATH=`
# here would only help checks later in THIS SAME script, never a separate
# later tool call's `npm install`. Symlinking into a directory that's
# already on every fresh shell's default PATH (no rc file needs sourcing)
# is what makes a fix here actually stick for the rest of the run.
persist_bin() {
  local src="$1" name="$2"
  local dir
  for dir in /usr/local/bin /usr/bin; do
    if { [ -w "$dir" ] || [ "$(id -u)" = "0" ]; } 2>/dev/null; then
      if ln -sf "$src" "$dir/$name" 2>/dev/null; then
        note "linked $dir/$name -> $src"
        return 0
      fi
    fi
  done
  warn "could not persist $name into /usr/local/bin or /usr/bin (no writable/root access) — it will only resolve for the rest of THIS script, not later tool calls"
  return 1
}

# ---------------------------------------------------------------------------
# Self-heal pass (sandbox only, harmless no-op otherwise): if a runtime
# isn't resolving, it's frequently already installed somewhere a
# non-interactive shell never sourced (nvm/volta/fnm's init script) rather
# than genuinely absent. Find it and persist it before concluding it's
# actually missing. PATH is also exported here so the rest of THIS script
# sees it immediately.
heal_path_from_known_installers() {
  local candidates=(
    "$HOME/.volta/bin"
    "$HOME/.fnm"
    "/opt/homebrew/bin"
  )
  if [ -d "$HOME/.nvm/versions/node" ]; then
    for d in "$HOME"/.nvm/versions/node/*/bin; do
      [ -d "$d" ] && candidates+=("$d")
    done
  fi
  local found=""
  for d in "${candidates[@]}"; do
    if [ -x "$d/node" ]; then
      found="$d"
      case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
    fi
  done
  export PATH
  if [ -n "$found" ]; then
    persist_bin "$found/node" "node"
    [ -x "$found/npm" ] && persist_bin "$found/npm" "npm"
    [ -x "$found/npx" ] && persist_bin "$found/npx" "npx"
  fi
}
heal_path_from_known_installers

# ---------------------------------------------------------------------------
# Last resort (sandbox only): install Node from its own official binary
# release — never a third-party curl-|-bash script. Downloads the exact
# tarball nodejs.org publishes for this OS/arch and verifies it against
# nodejs.org's own published SHASUMS256.txt before extracting anything.
# Bump NODE_INSTALL_VERSION periodically; override per-run with
# UAB_NODE_VERSION if a newer one is needed sooner.
NODE_INSTALL_VERSION="${UAB_NODE_VERSION:-22.11.0}"

install_node_from_official_tarball() {
  command -v curl >/dev/null 2>&1 || { warn "curl not available — cannot self-install Node"; return 1; }
  command -v tar  >/dev/null 2>&1 || { warn "tar not available — cannot self-install Node"; return 1; }

  local os_tag arch_tag
  case "$(uname -s)" in
    Linux) os_tag="linux" ;;
    *) warn "self-install only supports Linux sandboxes (detected: $(uname -s))"; return 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)  arch_tag="x64" ;;
    aarch64|arm64) arch_tag="arm64" ;;
    *) warn "unsupported architecture for self-install: $(uname -m)"; return 1 ;;
  esac

  local base="node-v${NODE_INSTALL_VERSION}-${os_tag}-${arch_tag}"
  local tmp; tmp="$(mktemp -d)"
  local sha_tool; sha_tool="$(_sha256_tool)" || true

  # .tar.gz first — gzip decompression is built into essentially every tar
  # implementation with no separate binary needed, unlike .tar.xz, which
  # needs a standalone `xz` (or liblzma) present. A minimal/stripped-down
  # sandbox image is far more likely to be missing `xz` than gzip support,
  # which is exactly what happened here: the download succeeded but
  # `tar -xJf` failed for want of `xz`. Try .tar.xz only as a fallback, in
  # case some future image is somehow the opposite (has xz, not gzip).
  local install_bin=""
  for fmt in "tar.gz:xzf:z" "tar.xz:xJf:J"; do
    local ext="${fmt%%:*}"
    local rest="${fmt#*:}"
    local tar_flag="${rest%%:*}"
    local archive="$tmp/$base.$ext"
    local url="https://nodejs.org/dist/v${NODE_INSTALL_VERSION}/${base}.${ext}"

    note "downloading official Node.js v${NODE_INSTALL_VERSION} ($arch_tag, .$ext) from nodejs.org..."
    if ! curl -fsSL -m 60 -o "$archive" "$url"; then
      warn "download failed ($url) — nodejs.org may be unreachable from this sandbox (separate from the npm registry check below)"
      continue
    fi

    if [ -n "$sha_tool" ] && curl -fsSL -m 30 -o "$tmp/SHASUMS256.txt" "https://nodejs.org/dist/v${NODE_INSTALL_VERSION}/SHASUMS256.txt" 2>/dev/null; then
      local expected actual
      expected="$(grep " ${base}.${ext}\$" "$tmp/SHASUMS256.txt" | awk '{print $1}')"
      actual="$($sha_tool "$archive" 2>/dev/null | awk '{print $1}')"
      if [ -n "$expected" ] && [ "$expected" != "$actual" ]; then
        warn "checksum mismatch for $base.$ext (expected $expected, got $actual) — refusing to install"
        rm -f "$archive"
        continue
      fi
      note "download checksum verified against nodejs.org's published SHASUMS256.txt"
    else
      warn "could not verify the download's checksum (no sha tool or SHASUMS256.txt unreachable) — proceeding anyway since the file came over TLS directly from nodejs.org"
    fi

    local dest_root="/opt/uab-node"
    if ! mkdir -p "$dest_root" 2>/dev/null; then
      dest_root="$HOME/.uab-node"
      mkdir -p "$dest_root" || { warn "could not create an install directory anywhere"; rm -rf "$tmp"; return 1; }
    fi
    if ! tar "-${tar_flag}" "$archive" -C "$dest_root" 2>/dev/null; then
      warn "extracting $base.$ext failed (likely missing '$([ "$ext" = tar.gz ] && echo gzip || echo xz)' decompression support in tar) — trying the other archive format"
      rm -f "$archive"
      continue
    fi

    if [ -x "$dest_root/$base/bin/node" ]; then
      install_bin="$dest_root/$base/bin"
      break
    fi
    warn "extracted $base.$ext but $dest_root/$base/bin/node is missing"
  done
  rm -rf "$tmp"

  if [ -z "$install_bin" ]; then
    warn "could not obtain a working Node.js build in either .tar.gz or .tar.xz form"
    return 1
  fi

  PATH="$install_bin:$PATH"
  export PATH
  persist_bin "$install_bin/node" "node"
  persist_bin "$install_bin/npm" "npm"
  [ -x "$install_bin/npx" ] && persist_bin "$install_bin/npx" "npx"
  INSTALLED+=("Node.js v${NODE_INSTALL_VERSION} -> $install_bin")
  return 0
}

if [ "$APP_TYPE" = "web" ]; then
  node_ok=1
  if ! command -v node >/dev/null 2>&1 || ! probe node --version; then
    node_ok=0
  else
    NODE_MAJOR="$(node --version | sed -E 's/^v([0-9]+).*/\1/')"
    if [ -n "$NODE_MAJOR" ] && [ "$NODE_MAJOR" -lt 22 ] 2>/dev/null; then
      note "found node $(node --version) but this skill's generated apps require >= 22 (node:sqlite) — treating as not-yet-satisfied"
      node_ok=0
    fi
  fi

  if [ "$node_ok" = "0" ] && [ "$SANDBOX_DETECTED" = "1" ]; then
    if install_node_from_official_tarball; then
      if probe node --version; then
        NODE_MAJOR="$(node --version | sed -E 's/^v([0-9]+).*/\1/')"
        [ -n "$NODE_MAJOR" ] && [ "$NODE_MAJOR" -ge 22 ] 2>/dev/null && node_ok=1
      fi
    fi
  fi

  if [ "$node_ok" = "1" ]; then
    note "node $(node --version) at $(command -v node)"
  else
    if [ "$SANDBOX_DETECTED" = "1" ]; then
      add_problem "node was missing/too old and the self-install fallback also failed (see WARN lines above) — likely nodejs.org is unreachable from this sandbox, or the OS/arch isn't Linux x64/arm64"
    else
      add_problem "node did not resolve, did not run, or is older than the required >=22 (tried: $(command -v node 2>/dev/null || echo 'not on PATH'))"
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
  # timeout. Self-install can't fix this — it's not a missing-tool problem.
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

  # Python has no equivalent official portable tarball the way Node does
  # (a real interpreter build needs either the OS's package manager or a
  # from-source build) — the one safe, well-known first-party fallback in
  # a detected sandbox is the OS's own package manager, not a third-party
  # build. Only attempted as root with apt-get present.
  if [ -z "$PYTHON_BIN" ] && [ "$SANDBOX_DETECTED" = "1" ] && [ "$(id -u)" = "0" ] && command -v apt-get >/dev/null 2>&1; then
    note "python missing in a detected sandbox — attempting 'apt-get install -y python3 python3-pip' (root + apt-get present)"
    if apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq python3 python3-pip >/dev/null 2>&1; then
      for candidate in python3 python; do
        if probe "$candidate" --version; then
          PYTHON_BIN="$candidate"
          INSTALLED+=("python3/pip via apt-get")
          break
        fi
      done
    else
      warn "apt-get install python3 failed — see apt's own output by running it directly if you need more detail"
    fi
  fi

  if [ -z "$PYTHON_BIN" ]; then
    if [ "$SANDBOX_DETECTED" = "1" ]; then
      add_problem "neither python3 nor python resolved and ran, and this sandbox has no apt-get+root path to self-install one — Python has no official portable tarball the way Node does, so this needs the sandbox image itself to include Python"
    else
      add_problem "neither python3 nor python resolved and ran (checked both — see verify-worker-app.sh's note on Windows Store alias stubs)"
    fi
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
if [ "${#INSTALLED[@]}" -gt 0 ]; then
  echo "-- self-installed during this run (sandbox detected):"
  for i in "${INSTALLED[@]}"; do echo "     - $i"; done
fi

if [ "${#PROBLEMS[@]}" -eq 0 ]; then
  echo "PASS: this sandbox can run the $APP_TYPE verify/build/install steps"
  exit 0
fi

echo "FAIL: this sandbox is missing something the $APP_TYPE app needs before generation is worth starting:"
for p in "${PROBLEMS[@]}"; do
  echo "  - $p"
done
echo
if [ "$SANDBOX_DETECTED" = "1" ]; then
  echo "This was detected as an ephemeral automation sandbox, so the self-install"
  echo "fallback above was already attempted and did not fully succeed — see the"
  echo "WARN lines above for why (most likely: no network route to nodejs.org/"
  echo "pypi.org/npm registry, or an unsupported OS/architecture). There is no"
  echo "human present to act on 'please install Node.js' here; report the exact"
  echo "list above, including the PATH line and any WARN lines, to whoever"
  echo "maintains the TrueForge/Daytona sandbox image or its network egress"
  echo "rules — that's the only remaining fix."
else
  echo "Do not generate the app yet. See references/git-workflow.md for what to"
  echo "tell the project leader. If this IS actually an ephemeral sandbox that"
  echo "the detection above missed, re-run with UAB_FORCE_SANDBOX=1 to allow the"
  echo "self-install fallback, and report what environment signal identifies"
  echo "this platform so the detection can be extended."
fi
exit 1
