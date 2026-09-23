#!/usr/bin/env bash
# Mechanizes the parts of references/verification-checklist.md that are
# actually mechanical — grep/test assertions, not judgment calls. A model
# that reliably runs a script and reacts to a printed FAIL line is a much
# lower bar than one that reliably self-audits a 15-item prose checklist
# from memory across many tool calls, and this exists to move as many
# checklist items as possible onto that lower bar.
#
# This does NOT replace verification-checklist.md — genuinely subjective
# items (does the logo look right, does the manifest match what was
# actually generated) stay there, called out explicitly at the top of
# that file as "still manual". This only covers what can be asserted by a
# script the same way every time.
#
# Run from the generated app's repo root. Exit 0 = every mechanical check
# passed. Exit 1 = prints every failure found (not just the first) so a
# model doesn't need N separate runs to discover N separate problems.
set -uo pipefail

FAILS=()
fail_item() { FAILS+=("$1"); }

APP_TYPE="${1:-}"
if [ -z "$APP_TYPE" ]; then
  if [ -f package.json ]; then APP_TYPE="web"
  elif [ -f requirements.txt ]; then APP_TYPE="worker"
  else
    echo "FAIL: could not auto-detect app type (no package.json or requirements.txt in $(pwd)) — pass it explicitly: scripts/lint-checklist.sh web|worker" >&2
    exit 1
  fi
fi

echo "== lint-checklist: $APP_TYPE app in $(pwd) =="

# ---------------------------------------------------------------------------
# Shared: .gitignore / .dockerignore / local-artifact hygiene
# ---------------------------------------------------------------------------
if [ ! -f .gitignore ]; then
  fail_item ".gitignore is missing"
else
  for pattern in '.env' '.data' '.localstorage'; do
    grep -qF "$pattern" .gitignore || fail_item ".gitignore does not cover '$pattern'"
  done
  # .env*.local (not just .env.local) must be covered — see data-layer.md.
  grep -qE '^\.env\*\.local$|^\.env\*$' .gitignore || fail_item ".gitignore does not cover '.env*.local' (a bare '.env.local' line alone is not enough — see data-layer.md)"
fi

if [ ! -f .dockerignore ]; then
  fail_item ".dockerignore is missing at the repo root"
else
  for pattern in '.env' '.data' '.localstorage'; do
    grep -qF "$pattern" .dockerignore || fail_item ".dockerignore does not cover '$pattern'"
  done
fi

if [ -f .env.template ]; then
  # Heuristic only (soft signal, not authoritative) — flags only known
  # secret-key/token PREFIXES (high precision, near-zero false-positive
  # risk). Deliberately does NOT flag on generic value length: this
  # skill's own placeholder convention (env-template.md) produces long,
  # lowercase-containing strings like "https://YOUR_ENDPOINT_HERE" or
  # "YOUR_HYDRA_AUTHORITY_URL" that a length-only heuristic would wrongly
  # flag. The exhaustive "no real value anywhere" judgment call stays in
  # verification-checklist.md as a manual item.
  if grep -nE '=(sk-|AKIA|ghp_|glpat-|xox[baprs]-|AIza)[A-Za-z0-9_/+=-]+' .env.template >/dev/null 2>&1; then
    fail_item ".env.template appears to contain a real API key/token (matches a known secret prefix — see: grep -nE '=(sk-|AKIA|ghp_|glpat-|xox[baprs]-|AIza)' .env.template)"
  fi
fi

# ---------------------------------------------------------------------------
# Web app (Next.js) checks
# ---------------------------------------------------------------------------
if [ "$APP_TYPE" = "web" ]; then
  [ -f package-lock.json ] || fail_item "package-lock.json is missing — npm ci in the Dockerfile fails without it, and package-app.sh ships it in the zip"

  if [ -f package.json ]; then
    grep -q '"better-sqlite3"' package.json && fail_item "package.json lists better-sqlite3 — must use the built-in node:sqlite (Node >= 22) instead, see data-layer.md"
  fi

  if [ -f Dockerfile ]; then
    # Every FROM node:<major>[...] stage must be >= 22.
    while IFS= read -r ver; do
      [ -n "$ver" ] || continue
      if [ "$ver" -lt 22 ] 2>/dev/null; then
        fail_item "Dockerfile has a FROM node:$ver stage — must be node:22-alpine or newer in every stage (node:sqlite requires Node >= 22)"
      fi
    done < <(grep -oE 'FROM node:[0-9]+' Dockerfile | grep -oE '[0-9]+$')
    grep -qE '^FROM node:[0-9]+' Dockerfile || fail_item "Dockerfile has no 'FROM node:<version>' stage — cannot confirm Node version"
  else
    fail_item "Dockerfile is missing"
  fi

  # -- env vars: no NEXT_PUBLIC_ leak beyond the three known auth vars -----
  ALLOWED_PUBLIC_VARS='NEXT_PUBLIC_AUTH_URL|NEXT_PUBLIC_CLIENT_ID|NEXT_PUBLIC_REDIRECT_URL'
  while IFS=: read -r file var; do
    [ -n "$var" ] || continue
    echo "$var" | grep -qE "^($ALLOWED_PUBLIC_VARS)$" || fail_item "$file references \$$var — no external-integration env var may be prefixed NEXT_PUBLIC_ (it would ship in the client bundle), only the three auth vars may be"
  done < <(grep -rhoE '\bNEXT_PUBLIC_[A-Z0-9_]+' src .env.template .env.local 2>/dev/null \
            | sort -u \
            | while read -r v; do grep -rl "$v" src .env.template .env.local 2>/dev/null | while read -r f; do echo "$f:$v"; done; done)

  # -- auth wiring (only meaningful if this app has login at all) ----------
  if [ -f src/auth/oidcConfig.ts ]; then
    grep -q 'onSigninCallback' src/auth/oidcConfig.ts || fail_item "src/auth/oidcConfig.ts is missing onSigninCallback — every login leaves a spent auth code in the address bar without it"
    grep -qE "client_id:|redirect_uri:|response_type:" src/auth/oidcConfig.ts || fail_item "src/auth/oidcConfig.ts does not use oidc-client-ts's snake_case field names (client_id/redirect_uri/response_type)"
    grep -qE 'clientId:|redirectUri:|responseType:' src/auth/oidcConfig.ts && fail_item "src/auth/oidcConfig.ts uses oidc-react's old camelCase field names (clientId/redirectUri/responseType) — these are silently ignored by oidc-client-ts, use client_id/redirect_uri/response_type"
    grep -q 'post_logout_redirect_uri' src/auth/oidcConfig.ts && fail_item "src/auth/oidcConfig.ts sets post_logout_redirect_uri — must be omitted here and forced to '' at each signoutRedirect() call site instead, see auth-hydra-oidc.md"

    [ -f src/auth/useOptionalAuth.ts ] || fail_item "src/auth/oidcConfig.ts exists (login is on) but src/auth/useOptionalAuth.ts is missing"

    # Every auth consumer must import useOptionalAuth(), never
    # react-oidc-context's useAuth() directly — except the two files that
    # legitimately touch the raw library: useOptionalAuth.ts itself (it
    # wraps AuthContext) and AuthProviderWrapper.tsx (its
    # AuthErrorUrlCleanup child legitimately calls useAuth()).
    while IFS= read -r f; do
      case "$f" in
        src/auth/useOptionalAuth.ts|src/auth/AuthProviderWrapper.tsx) ;;
        *) fail_item "$f imports useAuth() directly from react-oidc-context — must import useOptionalAuth() from src/auth/useOptionalAuth.ts instead" ;;
      esac
    done < <(grep -rlE "import[^;]*\buseAuth\b[^;]*from ['\"]react-oidc-context['\"]" src 2>/dev/null)

    if grep -rq 'removeUser(' src 2>/dev/null; then
      fail_item "removeUser( appears in src/ — sign-out must call signoutRedirect(), not removeUser() alone (removeUser() clears local tokens but leaves Hydra's SSO session alive)"
    fi

    if [ -f src/components/layout/AppShell.tsx ] || [ -f src/auth/AuthProviderWrapper.tsx ]; then
      [ -f src/auth/AuthProviderWrapper.tsx ] || fail_item "login is on but src/auth/AuthProviderWrapper.tsx is missing"
    fi
  fi

  # -- branding: logo + AppBar -------------------------------------------
  [ -f public/uab-logo-white.png ] || fail_item "public/uab-logo-white.png is missing (should be copied from the bundled assets/uabCoreLogoWhiteSmall.png, see branding-theme.md)"
  if [ -f src/components/layout/AppShell.tsx ]; then
    grep -q 'uab-logo-white.png' src/components/layout/AppShell.tsx || fail_item "src/components/layout/AppShell.tsx does not reference /uab-logo-white.png"
    grep -q 'next/image' src/components/layout/AppShell.tsx && fail_item "src/components/layout/AppShell.tsx imports next/image — the logo must be a plain <img>, never next/image"
    grep -qE "maxWidth:\s*270" src/components/layout/AppShell.tsx || fail_item "src/components/layout/AppShell.tsx's logo is not styled with maxWidth: 270"
    grep -qE "height:\s*'auto'" src/components/layout/AppShell.tsx || fail_item "src/components/layout/AppShell.tsx's logo does not set height: 'auto' (a fixed height alongside maxWidth stretches/squishes it)"
    grep -qE "theme\.palette\.primary\.main" src/components/layout/AppShell.tsx || fail_item "src/components/layout/AppShell.tsx's AppBar does not reference theme.palette.primary.main — the bar must be fixed UAB Green, never mode-dependent"
  else
    fail_item "src/components/layout/AppShell.tsx is missing"
  fi

  # -- Footer ---------------------------------------------------------------
  if [ -f src/components/layout/Footer.tsx ]; then
    for needle in 'Contact UAB' 'Privacy' 'Terms of Use' 'Nondiscrimination Statement' 'University of Alabama at Birmingham'; do
      grep -qF "$needle" src/components/layout/Footer.tsx || fail_item "src/components/layout/Footer.tsx is missing required text: \"$needle\""
    done
    grep -qi 'A-Z Site Index' src/components/layout/Footer.tsx && fail_item "src/components/layout/Footer.tsx includes an A-Z Site Index link — generated apps must intentionally omit it"
  else
    fail_item "src/components/layout/Footer.tsx is missing"
  fi

  # -- Drawer layout (only if a Drawer nav was generated) -------------------
  if [ -f src/components/layout/AppShell.tsx ] && grep -q '<Drawer' src/components/layout/AppShell.tsx; then
    grep -qE "minWidth:\s*0" src/components/layout/AppShell.tsx || fail_item "AppShell.tsx has a Drawer but its main content Box is missing minWidth: 0 — without it a flex child can force the page wider than the viewport"
    grep -q 'variant="permanent"' src/components/layout/AppShell.tsx || fail_item "AppShell.tsx has a Drawer but no variant=\"permanent\" branch for desktop"
    grep -q 'variant="temporary"' src/components/layout/AppShell.tsx || fail_item "AppShell.tsx has a Drawer but no variant=\"temporary\" branch for mobile"
  fi

# ---------------------------------------------------------------------------
# Worker app (Python/FastAPI) checks
# ---------------------------------------------------------------------------
elif [ "$APP_TYPE" = "worker" ]; then
  [ -f requirements.txt ] || fail_item "requirements.txt is missing"
  if [ -f Dockerfile ]; then
    grep -qE '^FROM python:' Dockerfile || fail_item "Dockerfile has no 'FROM python:<version>' stage"
  else
    fail_item "Dockerfile is missing"
  fi
fi

# ---------------------------------------------------------------------------
echo
if [ "${#FAILS[@]}" -eq 0 ]; then
  echo "PASS: all mechanical checklist items passed"
  exit 0
fi

echo "FAIL: ${#FAILS[@]} mechanical checklist item(s) failed:"
for f in "${FAILS[@]}"; do
  echo "  - $f"
done
echo
echo "Fix every item above, then re-run this script. This does not replace"
echo "references/verification-checklist.md — its remaining judgment-based"
echo "items (marked 'still manual' there) still need a human/agent read-through."
exit 1
