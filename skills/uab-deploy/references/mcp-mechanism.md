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

## Still needs verification before this is trusted in production

`scripts/deploy.py`'s header comment repeats this list — update both
places if any item below gets confirmed or turns out wrong (items 1, 2 and
5 of the original list are resolved above; numbering is kept for history):

3. **File execution vs. inline script source.** Confirm whether
   `scripts/deploy.py`, checked in as a normal file, can be executed
   directly in the sandbox (`python3 scripts/deploy.py --args...`) and
   successfully `import mcp_client` — or whether Code Mode only exposes
   `mcp_client` to script *source text* the agent passes inline to a
   Code-Mode-specific invocation. If it's the latter, `SKILL.md` needs to
   instruct the agent to read this file's contents and pass them as the
   script body, rather than "run this file" — the logic inside the script
   is identical either way, only how it gets invoked changes.
4. **`call_tool`'s Python result/error shape.** `deploy.py`'s `payload()`
   accepts every shape an MCP result can take (structured content, JSON in
   text content blocks, a plain string, an `isError` result), and
   `classify()` sorts failures by message text: tool not found
   (`tool '…' not found`, as Bifrost reports it), connector not
   configured, permission, or transient. Confirm the exact exception type
   and return object `call_tool` uses and tighten both once known —
   string-matching is defensive, not a final design.

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
the tools appear as `github-create_repository`, `github-list_branches`,
`github-create_branch`, `github-push_files` and `github-get_me`, so match
those names in the policy.

The gateway also has its own allowlist: every tool above must be enabled
for the `github` MCP client and the virtual key TrueForge's `bifrost`
connector uses, or the call fails with `MCP_TOOL_NOT_FOUND`.

## Why this replaced git entirely

An earlier version of this skill used plain shell `git` with an
unconfirmed Daytona-SDK fallback for sandboxes without a `git` binary.
The MCP/Code Mode mechanism above eliminates that uncertainty structurally
— there's no git binary dependency at all, and no in-sandbox credential to
protect — so the git-based path (and its `GIT_ASKPASS`/token-env-var
machinery) was removed rather than kept as a fallback.
