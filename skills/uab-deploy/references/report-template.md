# Report-back templates

Plain language, no jargon dump — this is read by whoever is watching the
session, who may not be technical. Never say "deployed" or "live" —
this skill only pushes a branch; hosting/deployment beyond that is a
separate step it never takes.

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
> If a pull request already exists from this branch, it now includes this
> update automatically. Nothing else happened beyond this push.

## On failure — MCP connector not configured

> I couldn't push **&lt;app-name&gt;**'s code — the GitHub connector
> (`<mcp-server-name>`) isn't available in this session. This is a
> TrueForge configuration issue (check `Settings → Connectors`), not
> something fixable from here. Nothing was touched — no repo, branch, or
> commit was created anywhere.

## On failure — permission/scope rejected

> I attempted to push **&lt;app-name&gt;**'s code to `<owner>/<repo>`,
> but the request was rejected — the GitHub connector's token doesn't
> appear to have permission for this &lt;repository/organization&gt;
> (or its scope doesn't allow &lt;creating repos/pushing to this
> branch&gt;). Next step: check the connector's configured scope in
> `Settings → Connectors`, then this can be re-run.

## On failure — branch diverged

> I attempted to push **&lt;app-name&gt;**'s update to
> `deploy/<app-slug>` in `<owner>/<repo>`, but something else has already
> changed that branch since the last run here. I did **not** overwrite
> it — the target repo's branches are untouched. Someone needs to look at
> `deploy/<app-slug>` directly and decide how to reconcile it before this
> can be re-run.
