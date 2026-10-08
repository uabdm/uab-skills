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

## Review cycles: one branch + one PR per cycle

A user can come back to an app many times. Each **review cycle** is one
deploy branch and one pull request into `--target-branch`:

| What GitHub shows for the app's deploy branch | This run |
|---|---|
| Branch exists, PR **open** (or no PR at all) | **Reuse** it — the revision lands as a new commit on the same PR. Never recreate it from `--target-branch` (that would drop what's already there). |
| Branch exists, PR **merged**, no open PR | The cycle is finished: start **`deploy/<app-slug>-<YYYYMMDD-HHMM>`** from `--target-branch`, and open a new PR |
| Branch doesn't exist (first deploy, or GitHub's "automatically delete head branches" removed it after the merge) | Create **`deploy/<app-slug>`** from `--target-branch`, open a PR |

Which branch is "the app's" comes from `--deploy-branch-name`, else the
deploy state (below), else `deploy/<app-slug>`. PRs are looked up with
`list_pull_requests` (`head=<owner>:<branch>`, `state=all`). Recommend that
repo owners turn on **Settings → General → Automatically delete head
branches**: then every cycle can use the plain `deploy/<app-slug>` name.

New branches are created with `create_branch` and `from_branch:
<target-branch>` — the tool branches from a branch *name*, not a SHA (the
fresh-repo edge case is in `SKILL.md`'s deploy flow step c). There is no
force-push-shaped operation on this path at all (see
`references/mcp-mechanism.md`) — pushing means creating a commit via the
push tool, not updating a ref directly, so the class of bug a `--force`
flag would cause is structurally absent, not just prohibited by
convention.

## Deploy state and the divergence check

After each push (and each `--sync`), `deploy.py` writes a small JSON file
**outside** the app folder — `<parent of --source-dir>/.uab-deploy/<owner>__<repo>__<app-slug>.json`
— with the repo, the deploy branch, the branch tip it left, the PR link,
and the **git blob SHA of every file** it pushed (the same fingerprint
GitHub lists for each file). It is never pushed or zipped.

Before every push the script lists the files on GitHub (directory
listings via `get_file_contents`, which do pass through the gateway) and
compares them with that record. Only **GitHub-side** changes matter —
the sandbox's own edits are the point of the round:

| Situation | Stop code | Meaning |
|---|---|---|
| Reusing the branch; a file this push would overwrite was changed or deleted on GitHub since we pushed it | `BRANCH_DIVERGED` | Someone (a reviewer, an IT person) edited the PR branch |
| New branch after a merge; a file we pushed before was changed on `--target-branch` since | `TARGET_CHANGED` | `main` moved on (edits in the PR before merge, or other work) |
| Reusing a branch with **no** state for it, and its files differ from the sandbox's | `BRANCH_NOT_TRACKED` | An older sandbox, a copied app, or someone else's branch — ownership can't be proven |

In all three cases **nothing is pushed**. The fix is the same: run
`--sync` (brings GitHub's version into the sandbox, backing up any local
file it replaces), re-apply the change, QA, deploy. `--adopt-branch`
skips the `BRANCH_NOT_TRACKED` stop — only on the user's explicit
decision. Files GitHub has that the sandbox doesn't touch (e.g. a logo a
reviewer uploaded by hand) never count as a conflict: the push doesn't
touch them.

**Stale files:** files this app pushed before that are no longer in the
app (deleted or renamed) stay in the repo, because the push is
additive-only. They're listed on a `STALE_ON_BRANCH:` line and in the PR
description so the reviewer can delete them — never deleted
automatically.

## `--sync`: restoring the app from GitHub

GitHub is the source of truth; the sandbox is a working copy that may be
gone (sandboxes are deleted after a few days) or behind. `--sync`:

1. Picks the source: the app's deploy branch if its PR is still open (or
   it has none), else `--target-branch` — or `--sync-from=<branch>`.
2. Lists every file on it (`get_file_contents` on directories, with
   `fields: [path, type, sha, size, download_url]`).
3. Downloads each missing/different file from its `download_url` (bytes,
   so binary files restore exactly), checks it against the listed SHA,
   and writes it. A replaced local file is first copied to
   `.uab-deploy/sync-backup-<UTC time>/`; files only present locally are
   kept and listed (`LOCAL_ONLY:`); excluded folders are untouched.
4. Records the synced snapshot as the deploy state, so the next deploy
   compares against it.

If a link has expired (they're short-lived), that folder is listed again
once for fresh links; a second failure stops with `SYNC_DOWNLOAD_FAILED`.
The links carry a token and are never printed. If the app references the
UAB logo but it isn't on GitHub (it can't be pushed), the script prints
`MISSING_ASSET:` — copy `uab-branding`'s `assets/uabCoreLogoWhiteSmall.png`
to `public/uab-logo-white.png`.

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

**Binary files are collected but not pushed.** The push tool carries
UTF-8 text only (see `references/mcp-mechanism.md`), so any file that
isn't valid UTF-8 text — images, fonts, other binary assets — is left out
of the commit and listed on the script's `SKIPPED_BINARY:` line. The
report names those files so someone can add them to the deploy branch
separately.

Collection (and the push tool it feeds) is **additive/overwrite only**:
files already in the target repo's destination path that this run's file
list doesn't itself include are left alone. `uab-deploy` never mirrors,
prunes, or deletes anything in the target repo beyond the paths in its
own `files` array — this is a structural property of the push-tool
mechanism (see `references/mcp-mechanism.md`), not something this skill
has to separately enforce.

## Known limitation

A re-run with no real changes still produces a commit with an identical
tree — the script doesn't skip the push when every fingerprint already
matches. Treat this as cosmetic, not a correctness or safety issue.

## Failure matrix

| Failure | Response |
|---|---|
| MCP connector not configured/reachable | Stop immediately, don't retry. Report as a TrueForge configuration problem. |
| GitHub tool not found on the connector | Stop, don't retry. Report the connector name and tool prefix used, and that the gateway's tool allowlist may be missing the tool. |
| Tool answered with an error (e.g. 404/422) | Stop, don't retry — it's a real answer, not a glitch. Report it as given. |
| Permission/scope error on any tool call | Stop, don't retry. Report as a connector-token-scope problem — never attempt to work around it. |
| Transient/network-looking failure | Retry up to twice with a short pause, then stop and report if still failing. |
| `BRANCH_DIVERGED` / `TARGET_CHANGED` / `BRANCH_NOT_TRACKED` | Nothing was pushed. `--sync`, re-apply the change, QA, deploy again. Never work around it. |
| `PR_NOT_OPENED` (push succeeded) | Report the push as done and the PR problem plainly (e.g. missing permission); the user can open the PR on GitHub. |
| `SYNC_REPO_MISSING` / `SYNC_SOURCE_MISSING` / `SYNC_EMPTY` | Nothing to restore from — check the repo URL and branch with the user. |
| `SYNC_DOWNLOAD_FAILED` | Stop; report which file. Files already restored stay; re-running `--sync` resumes (unchanged files are skipped). |
