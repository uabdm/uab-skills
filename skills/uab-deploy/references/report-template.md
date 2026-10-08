# Report-back templates

Plain language, no jargon dump — this is read by whoever is watching the
session, who may not be technical. Never say "deployed" or "live" —
this skill only pushes a branch; hosting/deployment beyond that is a
separate step it never takes.

## Skipped binary files (add to any success report when present)

If the script printed `SKIPPED_BINARY:`, add this to whichever success
template applies — plainly, not as a footnote:

> These files were **not** pushed, because the GitHub connector can only
> carry text files: `<path>`, `<path>`. They need to be added to
> **`deploy/<app-slug>`** separately (for example by uploading them on
> GitHub) before the app is complete.

## Pull request (add to any success report)

From the script's `PR:` line:

- **opened** → "I opened a pull request to merge it into
  `<target-branch>`: <url>. Merging it is the review step."
- **existing** → "The pull request that's already open for this app
  (<url>) now includes this update."
- `PR_NOT_OPENED` → "The code is on the branch, but I couldn't open the
  pull request (<reason>). You can open it on GitHub from
  `deploy/<app-slug>` into `<target-branch>`."

## Stale files (add to any success report when present)

If the script printed `STALE_ON_BRANCH:`:

> These files were part of an earlier version of the app but aren't any
> more: `<path>`, `<path>`. They're still in the repository (I never
> delete files there) — whoever reviews the pull request may want to
> remove them.

## On success — first deploy for this app, repo already existed

> I've pushed **&lt;app-name&gt;**'s code to a new branch,
> **`deploy/<app-slug>`**, in `<owner>/<repo>`. This is a new branch, not
> `<target-branch>` itself — merging it into `<target-branch>` is a
> separate step for whoever reviews it.
>
> QA status for this build: **&lt;qa-status&gt;**. &lt;&lt;&lt; if
> qa-status is not "passed": *This has not been confirmed to build, run,
> or pass QA in a real environment — say this plainly, not as a footnote.*
> &gt;&gt;&gt;
>
> Nothing else happened beyond this push — no hosting, no pipeline, no
> infrastructure was set up or touched.

## On success — first deploy, and the repo didn't exist yet

> `<owner>/<repo>` didn't exist yet, so I created it (&lt;private/public&gt;)
> and pushed **&lt;app-name&gt;**'s code to a new branch,
> **`deploy/<app-slug>`**, in it. Say this plainly — creating a new repo
> is a bigger action than a normal push, not a footnote.
>
> QA status for this build: **&lt;qa-status&gt;**. &lt;&lt;&lt; same caveat
> as above if not "passed" &gt;&gt;&gt;
>
> Nothing else happened beyond creating the repo and this push — no
> hosting, no pipeline, no other infrastructure was set up or touched.

## On success — update to an existing deploy branch

> I've pushed an update for **&lt;app-name&gt;** to its existing branch,
> **`deploy/<app-slug>`**, in `<owner>/<repo>` (this branch already
> existed from a previous run — this adds a new commit on top of it,
> nothing was rewritten).
>
> QA status for this build: **&lt;qa-status&gt;**. &lt;&lt;&lt; same
> caveat as above if not "passed" &gt;&gt;&gt;
>
> The pull request for this branch (<url>) now includes this update.
> Nothing else happened beyond this push.

## On success — new review round after the previous one was merged

> The last version of **&lt;app-name&gt;** was already merged into
> `<target-branch>`, so I put these changes on a new branch,
> **`<deploy-branch>`**, based on the current `<target-branch>`, and
> opened a new pull request for them: <url>.
>
> QA status for this build: **&lt;qa-status&gt;**. &lt;&lt;&lt; same
> caveat as above if not "passed" &gt;&gt;&gt;
>
> Nothing else happened beyond this push.

## On failure — MCP connector not configured

> I couldn't push **&lt;app-name&gt;**'s code — the connector that carries
> the GitHub tools (`<mcp-server-name>`, normally the `bifrost` gateway)
> isn't available in this session. This is a
> TrueForge configuration issue (check `Settings → Connectors`), not
> something fixable from here. Nothing was touched — no repo, branch, or
> commit was created anywhere.

## On failure — GitHub tools not found on the connector

> I couldn't push **&lt;app-name&gt;**'s code — the connector
> (`<mcp-server-name>`) is reachable, but it doesn't offer the GitHub
> tools this needs (looked for `<tool-prefix><tool>` and `<tool>`). This
> is a configuration issue: check that the connector name is right and
> that the gateway allows `create_repository`, `list_branches`,
> `create_branch`, `push_files`, `get_me`, `get_file_contents`,
> `list_pull_requests` and `create_pull_request` for this connector.
> Nothing was touched — no repo, branch, or commit was created anywhere.

## On failure — permission/scope rejected

> I attempted to push **&lt;app-name&gt;**'s code to `<owner>/<repo>`,
> but the request was rejected — the GitHub connector's token doesn't
> appear to have permission for this &lt;repository/organization&gt;
> (or its scope doesn't allow &lt;creating repos/pushing to this
> branch&gt;). Next step: check the connector's configured scope in
> `Settings → Connectors`, then this can be re-run.

## On a stop — someone else changed the code on GitHub

For `BRANCH_DIVERGED`, `TARGET_CHANGED` or `BRANCH_NOT_TRACKED`. Nothing
was pushed. Normally you then continue on your own: `--sync`, re-apply
the change, QA, deploy — and report the end result. Say what happened
first, plainly:

> Before pushing, I checked GitHub and found that &lt;someone changed
> `<file>` on the review branch since my last update / the main version
> of the app has changed since it was last merged / the branch
> `<deploy-branch>` has changes I can't account for&gt;. I didn't
> overwrite anything. I'll bring those changes into my copy first, re-apply
> your requested changes on top of them, re-test, and then push.

If re-applying isn't safe (the other change touches the same thing the
user asked to change in a conflicting way), stop and ask the user which
version to keep instead of choosing.

## After a sync

> I restored **&lt;app-name&gt;** from GitHub (&lt;its open review branch
> `<branch>` / `<target-branch>`, since the last version was merged&gt;) —
> &lt;N&gt; files. &lt;&lt;&lt; if SYNC_BACKUP: *My earlier, unpushed
> edits to `<path>` were replaced by the GitHub version; I kept a copy and
> will re-apply them.* &gt;&gt;&gt; &lt;&lt;&lt; if MISSING_ASSET: *The UAB
> logo isn't stored on GitHub, so I put the standard logo back from the
> branding kit.* &gt;&gt;&gt;
