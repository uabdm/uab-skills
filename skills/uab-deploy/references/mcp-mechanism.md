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

The one non-secret piece of configuration this skill needs is
`--mcp-server-name` (default `github`) — just the name the connector was
given in `Settings → Connectors`, so `call_tool` knows which configured
server to address.

## Needs verification before this is trusted in production

`scripts/deploy.py`'s header comment repeats this list — update both
places if any item below gets confirmed or turns out wrong:

1. **Exact tool names.** `deploy.py` assumes `create_repository`,
   `get_branch`, `create_branch`, and `push_files` — the commonly
   documented names on the official `github/github-mcp-server`. Confirm
   these against the actual configured connector using Code Mode's
   `get_tool_output_schema` before relying on them; a self-hosted or
   differently-versioned GitHub MCP server could name these differently
   or split/merge their responsibilities.
2. **Binary file support.** `deploy.py` base64-encodes every file's bytes
   and sends `{"path", "content", "encoding": "base64"}`. Confirm the
   actual `push_files`-equivalent tool accepts an `encoding` field (or
   however it signals non-text content) rather than assuming UTF-8 text
   only — this matters for any non-text asset a generated app might
   include (most `uab-branding` output is text/SVG, but don't assume no
   binary asset ever appears).
3. **File execution vs. inline script source.** Confirm whether
   `scripts/deploy.py`, checked in as a normal file, can be executed
   directly in the sandbox (`python3 scripts/deploy.py --args...`) and
   successfully `import mcp_client` — or whether Code Mode only exposes
   `mcp_client` to script *source text* the agent passes inline to a
   Code-Mode-specific invocation. If it's the latter, `SKILL.md` needs to
   instruct the agent to read this file's contents and pass them as the
   script body, rather than "run this file" — the logic inside the script
   is identical either way, only how it gets invoked changes.
4. **Error surface shape.** `deploy.py`'s `call()` wrapper classifies
   failures by string-matching whatever `call_tool` raises/returns
   (`"not found"`, `"permission"`, etc.). Confirm the actual exception
   type or structured error field `call_tool` produces on failure and
   tighten this classification once known — string-matching is a
   best-effort placeholder, not a final design.
5. **"Already exists" distinguishability.** `ensure_repo_exists()` treats
   a `create_repository` failure containing "already exists" as success
   and continues. Confirm this is actually how the connector reports an
   existing repo, and that it's distinguishable from an unrelated
   permission failure that happens to mention similar wording.

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
document the tradeoff, not enforce a choice.

## Why this replaced git entirely

An earlier version of this skill used plain shell `git` with an
unconfirmed Daytona-SDK fallback for sandboxes without a `git` binary.
The MCP/Code Mode mechanism above eliminates that uncertainty structurally
— there's no git binary dependency at all, and no in-sandbox credential to
protect — so the git-based path (and its `GIT_ASKPASS`/token-env-var
machinery) was removed rather than kept as a fallback.
