#!/usr/bin/env bash
# Calls https://api.github.com/user using the DEMO_API_TOKEN environment
# variable as a bearer token, to prove Daytona's Secrets proxy-substitution
# feature works: this sandbox's env var should hold only an opaque
# placeholder (e.g. dtn_secret_...), never a real GitHub token, and the
# real value should only ever be attached by Daytona's outbound proxy for
# this specific allowlisted host. See SKILL.md for the full mechanism and
# its hard limits (headers only, no query params, no transforms).
#
# This is a test/demo script, not a production API-calling pattern, and
# has nothing to do with uab-deploy's GitHub MCP connector.
set -uo pipefail

fail() {
  echo "FAIL: $1"
  exit 1
}

TOKEN_ENV_VAR="DEMO_API_TOKEN"
ENDPOINT="https://api.github.com/user"

echo "== checking $TOKEN_ENV_VAR is present =="
TOKEN_VALUE="${!TOKEN_ENV_VAR:-}"
if [ -z "$TOKEN_VALUE" ]; then
  fail "$TOKEN_ENV_VAR is unset or empty — the secret hasn't been attached to this sandbox. See SKILL.md's setup steps."
fi
echo "present (value is expected to be an opaque placeholder, not a real token — never printed here)"

echo "== calling $ENDPOINT =="
HTTP_STATUS="$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${TOKEN_VALUE}" \
  "$ENDPOINT")" || fail "curl itself failed to run — check network access from this sandbox"

echo "HTTP status: $HTTP_STATUS"

case "$HTTP_STATUS" in
  200)
    echo "PASS: real credential was substituted correctly by Daytona's proxy — this sandbox authenticated as a real GitHub account without ever holding that account's actual token."
    ;;
  401)
    echo "FAIL: substitution did not happen (401 Unauthorized). Check, in order: is the secret actually attached to this sandbox; was it just attached and the sandbox needs a restart to pick it up; does the secret's host allowlist include api.github.com; is the underlying token itself valid."
    exit 1
    ;;
  *)
    echo "FAIL: unexpected HTTP status $HTTP_STATUS — not interpreting this as pass or fail, check it directly."
    exit 1
    ;;
esac
