# MCP mechanism — how the push actually happens

`uab-deploy` never runs `git` and never sees a credential of any kind. It
pushes to GitHub entirely through a GitHub MCP server connector configured
once in TrueForge (`Settings → Connectors`), called through TrueForge's
**Code Mode** feature.

## How Code Mode + MCP fits together

Per TrueForge's own docs (`trueforge.dev/key-features/code-mode`): a script
running **inside this sandbox** can call

```python
from mcp_client import call_tool
result = await call_tool(server_name, tool_name, body={...})
```

The call itself is **bridged back to the harness**, which applies the
connector's stored credentials — quoting the docs directly: *"the sandbox
never holds tokens."* This is why `uab-deploy` has no token-handling
concerns at all (contrast with an earlier git-based design of this skill,
which had to carefully choreograph a `GIT_ASKPASS` callback to keep a
token out of any file — none of that exists here because there is no
token in this process to protect in the first place).

The non-secret configuration this skill needs is just an address:

- `--mcp-server-name` (default `bifrost`) — the name the connector was
  given in `Settings → Connectors`, so `call_tool` knows which configured
  server to address. By default that's the **Bifrost MCP gateway**, which
  fronts GitHub (and other servers) behind one connector and holds the
  GitHub token itself.
- `--tool-prefix` (default `github-`) — Bifrost exposes every upstream
  tool as `<server>-<tool>` (`github-push_files`), on its combined and
  per-server endpoints alike, with no option to turn that off. `deploy.py`
  tries `<prefix><tool>` first and falls back to the bare `<tool>`, so a
  direct GitHub connector (`--mcp-server-name=github`) works unchanged.

## Verified tool contract (2026-10-08)

Checked against the hosted GitHub MCP server (`api.githubcopilot.com/mcp/`)
directly and through Bifrost v2.2.6 (tool list and input schemas from the
gateway's `GET /api/mcp/clients`). This is what `deploy.py` relies on:

| Tool (bare name) | Parameters used | Notes |
|---|---|---|
| `list_branches` | `owner`, `repo`, `page`, `perPage` | Returns `[{name, commit: {sha}}]`. A missing repo answers with a 404 error result. **There is no `get_branch` tool** — this replaces it. |
| `get_me` | — | Returns the token's `login`; used to decide whether a new repo needs `organization`. |
| `create_repository` | `name`, `private`, `autoInit`, `organization` | No `owner` parameter; `organization` only when creating outside the token's own account. `autoInit` (camelCase) gives the repo its first commit. |
| `create_branch` | `owner`, `repo`, `branch`, `from_branch` | Branches from a branch **name**, not a SHA. |
| `push_files` | `owner`, `repo`, `branch`, `files`, `message` | Each file item allows **only** `{path, content}` (`additionalProperties: false`) and `content` is plain text. No `encoding` field; binary content can't be sent. |
| `get_file_contents` | `owner`, `repo`, `path`, `ref` (`refs/heads/<branch>`), `fields` | **Directories only.** Returns a JSON listing; with `fields: [path, type, sha, size, download_url]` each file has its blob `sha` and a `download_url`. Used for the divergence check and `--sync`. On a *file* it's useless through the gateway — see below. |
| `list_pull_requests` | `owner`, `repo`, `state: all`, `head: <owner>:<branch>`, `perPage` | Finds the deploy branch's PRs (open / merged). |
| `create_pull_request` | `owner`, `repo`, `title`, `head`, `base`, `body` | Opens the PR from the deploy branch into `--target-branch`. |

**The gateway drops file contents.** GitHub's server answers
`get_file_contents` on a *file* with two blocks: a text summary and the
file as an MCP **embedded resource**. Bifrost converts tool results to
text and replaces any embedded resource with a marker
(`core/mcp/utils.go`: `case mcp.EmbeddedResource:
result.WriteString(fmt.Sprintf("[Embedded Resource Response: %s]\n", ...))`),
so callers only ever see `successfully downloaded text file (SHA: …)[Embedded Resource Response: resource]`
— no content, and no setting changes it. **Directory listings are plain
JSON and come through intact**, including each file's `download_url`:
`https://raw.githubusercontent.com/<owner>/<repo>/<commit>/<path>?token=…`.
For private repos GitHub embeds a short-lived token that grants read
access to that one file only (verified 2026-10-08: with the token HTTP
200 and the exact bytes; without it, 404). The URL is pinned to a commit,
so one listing gives a consistent snapshot. `--sync` downloads each file
from it directly in the sandbox — the GitHub PAT still never enters the
sandbox — and never prints the URL. Trade-off: those links pass through
the gateway's logs and the agent's context while they're valid.

**Gateway allowlist.** Every tool in the table must be allowed for the
`github` MCP client in Bifrost (`toolsToExecute` in
`k8s\bifrost-values.yaml`) and for the virtual key TrueForge's `bifrost`
connector uses: `create_repository`, `create_branch`, `push_files`,
`list_branches`, `get_file_contents`, `get_me`, `list_pull_requests`,
`create_pull_request`. A missing one fails with `MCP_TOOL_NOT_FOUND`
(the PR tools degrade gracefully: the push still happens, with no PR
handling).

Consequences built into `deploy.py`:

- **Text only.** Files that aren't valid UTF-8 (or contain a NUL byte) are
  skipped and reported on a `SKIPPED_BINARY:` line, never pushed. Most
  `uab-branding` output is text/SVG, but generated apps can include images
  (e.g. a logo PNG) — those need adding to the deploy branch separately.
- **Repo existence is checked, not inferred.** `list_branches` runs first;
  `create_repository` is only called when the repo isn't found, so creation
  no longer depends on how an "already exists" error is worded.
- **Error results count as failures.** A tool can answer with an MCP error
  result (`isError`) instead of raising; `deploy.py` treats those as real,
  non-retryable answers.

## Confirmed in a live TrueForge run (2026-10-08)

`scripts/deploy.py`'s header comment repeats this — update both places if
anything below turns out different (items 1, 2 and 5 of the original
verification list are resolved above; numbering is kept for history):

3. **File execution works.** `scripts/deploy.py`, checked in as a normal
   file, runs directly in the sandbox (`python3 scripts/deploy.py ...`)
   and `import mcp_client` succeeds — no need to pass the source inline.
4. **`call_tool`'s result shape.** Observed live, through the `bifrost`
   connector:

   | Tool answer | What `call_tool` returns |
   |---|---|
   | JSON text (most GitHub tools, `registry_version`) | Already-parsed Python data: e.g. `{'serverName': 'agentregistry-mcp', 'version': 'v0.4.0'}`, or `[{'name': 'main', 'sha': '…', 'protected': False}]` for `list_branches` |
   | Non-JSON text — **including tool errors** | A list of MCP `TextContent` objects, e.g. `[TextContent(type='text', text='failed to list branches: GET https://api.github.com/repos/<owner>/<repo>/branches?...: 404 Not Found []')]` |

   **Errors are returned, not raised**, and the `isError` flag isn't
   exposed. So `deploy.py`'s `payload()` turns `TextContent` lists into
   text (or JSON), and `_raw_call()` treats GitHub-style error text
   (`failed to …`, or `: <4xx/5xx> <Status>`) as a failure: a 404 on
   `list_branches` means "repo doesn't exist", anything else is reported.
   Exceptions are still handled the same way in case a future
   `mcp_client` raises instead. `list_branches` items carry `sha` at the
   top level (`commit.sha` is also accepted).

## Operational caveat: approval policies still apply

Code Mode's docs state plainly: *"Approval policies still apply in Code
Mode — a script that calls a tool matching `require_approval_for_tools`
pauses for user approval just like a direct tool call."* If
`create_repository`, `create_branch`, `push_files`, or the branch-lookup
tool are covered by that policy in a given TrueForge instance, a deploy
that's supposed to run fully automatically right before sandbox teardown
will instead pause waiting on a human. `uab-deploy` cannot control or
detect this from inside the script. If fully unattended deploys are
wanted, whoever administers the TrueForge instance should exclude these
specific tools from `require_approval_for_tools` — this skill can only
document the tradeoff, not enforce a choice. Through the Bifrost gateway
the tools appear with a `github-` prefix (`github-create_repository`,
`github-list_branches`, `github-create_branch`, `github-push_files`,
`github-get_me`, `github-get_file_contents`, `github-list_pull_requests`,
`github-create_pull_request`), so match those names in the policy. The
gateway's own allowlist is described under "Gateway allowlist" above.

## Why this replaced git entirely

An earlier version of this skill used plain shell `git` with an
unconfirmed Daytona-SDK fallback for sandboxes without a `git` binary.
The MCP/Code Mode mechanism above eliminates that uncertainty structurally
— there's no git binary dependency at all, and no in-sandbox credential to
protect — so the git-based path (and its `GIT_ASKPASS`/token-env-var
machinery) was removed rather than kept as a fallback.
