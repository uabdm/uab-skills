# Branch & commit strategy

## Why a dedicated `deploy/<app-slug>` branch, never the literal `--target-branch`

`uab-app-builder/scripts/push-to-develop.sh` pushes straight onto a fixed
`develop` branch, and that's the right call *there* — that skill
provisions and owns the entire target repo for exactly one generated app,
so nothing else has a stake in that branch's history.

`uab-deploy`'s situation is different on purpose: even though it now
auto-creates the target repo if missing (see `SKILL.md`), a repo it
creates on this run may not stay solely its own forever — other commits,
branches, or a deployment pipeline could come to depend on
`--target-branch` specifically. This skill's push also happens
**unattended**, at sandbox-teardown time, with nobody reviewing it in the
moment — exactly the situation where landing directly on a shared branch
is riskiest if something about the caller's input is wrong.

A dedicated, namespaced branch (`deploy/<app-slug>` by default,
overridable via `--deploy-branch-name`) sidesteps the risk structurally:
creating a brand-new branch, or extending a branch this skill already
owns with one more commit, can never clobber history it doesn't control.
It also gives whoever reviews the deploy a normal, familiar unit to look
at — open a PR from `deploy/<app-slug>` into `--target-branch` — rather
than a commit buried in the target branch's own history.

## Branch-name derivation

- Default: `deploy/<app-slug>`, where `<app-slug>` comes from
  `--app-name` if given, else a slugified `--source-dir` folder name
  (lowercase, non-alphanumeric runs collapsed to a single `-`, trimmed).
- `--deploy-branch-name` overrides the whole derived name outright — use
  this when the caller wants a specific, predictable branch name instead
  (e.g. tying it to a ticket or session ID).

## Idempotent re-runs

Re-invoking `uab-deploy` for the same app (e.g. after a revision):

1. Look up whether the deploy branch already exists (`get_branch`-style
   call). If it does, this is a re-run — reuse it as-is, don't recreate it
   from `--target-branch`'s current tip (that would silently drop
   whatever's already on the deploy branch).
2. Collect the current `--source-dir` contents and push them as a new
   commit via the push tool, targeting the existing deploy branch.

This keeps one coherent history per app on its deploy branch, and keeps
any PR already opened against it valid across repeated generation/
revision cycles — reviewers see new commits land, not a branch that
vanished and reappeared. There is no force-push-shaped operation on this
path at all (see `references/mcp-mechanism.md`) — pushing means creating
a commit via the push tool, not updating a ref directly, so the class of
bug a `--force` flag would cause is structurally absent, not just
prohibited by convention.

If the deploy branch does **not** yet exist, this is the first deploy for
this app: create it from `--target-branch`'s tip commit SHA (resolved via
`get_branch`, with the fresh-repo edge case handled in `SKILL.md`'s deploy
flow step 3), then push the first commit to it.

## File-collection exclude list

Collect `--source-dir`'s contents (at `--target-subdir`, or the repo
root) excluding exactly:

```
node_modules/  .next/  .venv/  __pycache__/  .data/  .localstorage/
.git/  .verify/  .env  .env.local
```

This list is a deliberate duplicate of
`uab-app-creator-nobrand/scripts/package-app-fast.sh`'s own exclude
list — kept as its own copy in this skill rather than a shared import, the
same "stays self-contained" precedent `uab-app-qa/scripts/bg-run.sh`'s
header comment already sets for this codebase. If that list ever changes,
update both places.

`.gitignore` itself is an ordinary file and **is** collected — only the
`.git/` *directory* is excluded (it would hold the generated app's own
git metadata, if any exists — `uab-app-creator-nobrand` never runs git,
so in practice there normally isn't one, but exclude it defensively
regardless).

Collection (and the push tool it feeds) is **additive/overwrite only**:
files already in the target repo's destination path that this run's file
list doesn't itself include are left alone. `uab-deploy` never mirrors,
prunes, or deletes anything in the target repo beyond the paths in its
own `files` array — this is a structural property of the push-tool
mechanism (see `references/mcp-mechanism.md`), not something this skill
has to separately enforce.

## Known limitation

Unlike a `git diff --cached --quiet` check, there's no cheap way to
detect "nothing actually changed since the last deploy" before pushing —
that would require reading every existing file's content from the deploy
branch first and diffing, which is real extra round-trips for a case
(byte-identical re-run) that should be rare in practice. A re-run with no
real changes still produces a commit with an identical tree. Treat this
as a cosmetic limitation, not a correctness or safety issue.

## Failure matrix

| Failure | Response |
|---|---|
| MCP connector not configured/reachable | Stop immediately, don't retry. Report as a TrueForge configuration problem. |
| Permission/scope error on any tool call | Stop, don't retry. Report as a connector-token-scope problem — never attempt to work around it. |
| Transient/network-looking failure | Retry up to twice with a short pause, then stop and report if still failing. |
