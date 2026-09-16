#!/usr/bin/env bash
# Pushes the generated scaffold to `develop` — the one branch with no
# approval gate, which is what makes this safe to run as part of the
# "looks good" authorization already granted during the interview (see
# SKILL.md and references/git-workflow.md). This script refuses to run from
# any other branch and never touches `qa` or `production`.
#
# Run only after verification (verify-web-app.sh / verify-worker-app.sh)
# has passed. Run from the generated app's repo root.
set -uo pipefail

fail() {
  echo "FAIL: $1"
  exit 1
}

echo "== STEP 1: confirm current branch is develop =="
current_branch="$(git symbolic-ref --short -q HEAD || echo '')"
if [ "$current_branch" != "develop" ]; then
  fail "current branch is '$current_branch', not 'develop'. This script only ever pushes develop. Run scripts/setup-develop-branch.sh first, or find out why you're not on develop before pushing anything."
fi

echo "== STEP 2: check for a remote =="
if ! git remote -v | grep -q .; then
  echo "NO_REMOTE_CONFIGURED"
  echo "This is a local-only folder with nothing to push to yet. Tell the project leader: their IT team needs to connect this folder to an Azure Repos repository and push the develop branch themselves. Never invent or guess a remote URL."
  exit 0
fi
remote_name="$(git remote | head -n1)"
echo "found remote: $remote_name"

echo "== STEP 3: package-lock.json check (web apps only) =="
if [ -f package.json ] && [ ! -f package-lock.json ]; then
  echo "package-lock.json is missing — running npm install once to create it (npm ci in the Dockerfile and QA pipeline hard-fails without it)."
  npm install || fail "npm install failed while trying to create package-lock.json"
fi

echo "== STEP 4: stage and commit =="
git add -A
if git diff --cached --quiet; then
  echo "NOTHING_TO_COMMIT"
else
  git commit -m "Initial scaffold" || fail "git commit failed — see the error above"
fi

echo "== STEP 5: push =="
git push -u origin develop || fail "git push failed — read the error above (common causes: git identity not configured, remote rejected the push, no network). Resolve it, don't skip this step silently."

echo "PASS: develop pushed to $remote_name"
