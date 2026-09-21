#!/usr/bin/env bash
# Shared by verify-web-app.sh / verify-worker-app.sh (which write .verify/PASSED
# after a full pass) and package-app.sh (which refuses to zip unless the
# current source matches what was last verified). Source this file, don't
# execute it — it only defines compute_source_hash.
#
# The hash must be computed identically on both sides of that check.
# Sourcing this one file from every caller is what guarantees that; do not
# reimplement the hash logic separately in any script.

_sha256_tool() {
  if command -v sha256sum >/dev/null 2>&1; then
    echo "sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    echo "shasum -a 256"
  elif command -v openssl >/dev/null 2>&1; then
    echo "openssl dgst -sha256 -r"
  else
    return 1
  fi
}

# Hashes the content of every file that counts as "this app's source" —
# everything except reinstallable dependency/build output, local-only data,
# and the verification marker itself. This is deliberately the same set of
# directories package-app.sh already excludes from the handoff zip: if it
# doesn't ship and isn't reinstalled from a lockfile, a change to it doesn't
# require re-verification.
compute_source_hash() {
  local tool
  tool="$(_sha256_tool)" || {
    echo "FAIL: no sha256 tool found (tried sha256sum, shasum, openssl) — cannot compute a verification hash on this machine" >&2
    return 1
  }

  find . \
    \( -name node_modules -o -name .next -o -name .venv -o -name __pycache__ \
       -o -name .data -o -name .localstorage -o -name .git -o -name .verify \) -prune -o \
    -type f ! -name '*.zip' ! -name '.env' ! -name '.env.local' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 $tool 2>/dev/null \
    | $tool | awk '{print $1}'
}
