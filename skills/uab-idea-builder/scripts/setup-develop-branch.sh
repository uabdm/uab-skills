#!/usr/bin/env bash
# Gets the current directory onto a `develop` branch before any scaffold
# files are generated. See references/git-workflow.md for why this must
# happen first, and what to tell the project leader if git isn't installed.
#
# Every path here is local and non-destructive — it never touches or
# deletes anything on a remote. Run this with no arguments from the
# directory the app is being generated into.
set -uo pipefail

echo "== checking git =="
if ! git --version >/dev/null 2>&1; then
  echo "GIT_MISSING"
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "No git repository here yet — initializing one on develop."
  git init >/dev/null
  # Works whether or not this git version supports `git init -b develop`.
  git symbolic-ref HEAD refs/heads/develop
  echo "REPO_INITIALIZED_ON_DEVELOP"
  exit 0
fi

current_branch="$(git symbolic-ref --short -q HEAD || echo '')"

if [ "$current_branch" = "develop" ]; then
  echo "ALREADY_ON_DEVELOP"
  exit 0
fi

if git show-ref --verify --quiet refs/heads/develop; then
  git checkout develop
  echo "CHECKED_OUT_EXISTING_DEVELOP"
  exit 0
fi

if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  # No commits yet on this branch (unborn HEAD) — safe to just repoint it,
  # nothing has been committed to lose.
  git symbolic-ref HEAD refs/heads/develop
  echo "UNBORN_BRANCH_REPOINTED_TO_DEVELOP"
  exit 0
fi

branch_count="$(git branch --list | wc -l | tr -d ' ')"

if [ "$branch_count" -le 1 ]; then
  # Fresh single-branch repo (e.g. just "main") — local, non-destructive
  # rename. A later `git push origin develop` just pushes a new branch;
  # the remote's own branches (if any) are untouched until someone
  # explicitly acts on them.
  git branch -m develop
  echo "RENAMED_${current_branch}_TO_DEVELOP"
  exit 0
fi

# Multiple branches already exist, none called develop — branch off HEAD
# rather than renaming whatever we happen to be sitting on.
git checkout -b develop
echo "CREATED_NEW_DEVELOP_BRANCH"
exit 0
