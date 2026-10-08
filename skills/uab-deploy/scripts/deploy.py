#!/usr/bin/env python3
"""
Pushes an already-generated app's files (--source-dir, already on disk in
this sandbox) into a dedicated deploy/<app-slug> branch of a GitHub repo,
via a GitHub MCP server connector configured in TrueForge (Settings ->
Connectors) -- never git, never a token this script ever sees. See
SKILL.md and references/ for the full design. This is the single mandated
entry point for uab-deploy; never hand-roll individual call_tool
invocations by hand.

Run via TrueForge's Code Mode, which makes `mcp_client` importable inside
this sandbox:
    python3 scripts/deploy.py --repo-url=https://github.com/org/repo.git \\
      --target-branch=main --source-dir=/workspace/my-app

Repeat deploys (revisions): one review cycle = one deploy branch + one PR.
The branch is reused while its PR is open; after a merge a new branch is
started from --target-branch. A small deploy state (outside the app folder)
records what was pushed, and the script stops instead of overwriting
changes someone else made on GitHub (BRANCH_DIVERGED / TARGET_CHANGED /
BRANCH_NOT_TRACKED). Restore or refresh the app FROM GitHub with --sync:
    python3 scripts/deploy.py --sync --repo-url=... --target-branch=main \\
      --source-dir=/workspace/my-app
See references/branch-and-commit-strategy.md.

By default the GitHub tools are reached through the Bifrost MCP gateway
connector (`--mcp-server-name=bifrost`), which exposes them prefixed with
the upstream server's name (`github-create_repository`, ...). For a direct
GitHub connector, pass `--mcp-server-name=github`; the bare tool names are
tried automatically if the prefixed ones don't exist.

VERIFIED 2026-10-08 against the hosted GitHub MCP server
(api.githubcopilot.com/mcp/, via Bifrost v2.2.6) -- see
references/mcp-mechanism.md for the full table:
  - Tool names: create_repository, list_branches, create_branch,
    push_files, get_me. There is no get_branch tool.
  - create_repository takes {name, private, autoInit, organization} --
    no `owner`; `organization` only when creating outside your own account.
  - create_branch takes {owner, repo, branch, from_branch} -- no `sha`.
  - push_files items allow only {path, content} (additionalProperties:
    false) and content is plain text, so binary files are skipped and
    reported, never pushed.

CONFIRMED IN A LIVE TRUEFORGE RUN (2026-10-08, see references/mcp-mechanism.md):
  3. This file runs directly in the sandbox (`python3 scripts/deploy.py`)
     and `import mcp_client` works.
  4. call_tool's result shape: when the tool's text is JSON it comes back
     already parsed (dict/list); otherwise as a list of MCP TextContent
     objects. Tool errors (e.g. GitHub's "failed to list branches: ...
     404 Not Found") come back that same way, as text -- NOT raised.
     payload() turns TextContent into text/JSON, and _raw_call() treats
     GitHub-style error text as a failure.
"""
import argparse
import asyncio
import hashlib
import json
import os
import re
import shutil
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from urllib.parse import urlparse

# Bare tool names on the GitHub MCP server (verified 2026-10-08). Called as
# f"{--tool-prefix}{name}" first, falling back to the bare name.
CREATE_REPOSITORY_TOOL = "create_repository"
LIST_BRANCHES_TOOL = "list_branches"
CREATE_BRANCH_TOOL = "create_branch"
PUSH_FILES_TOOL = "push_files"
GET_ME_TOOL = "get_me"
GET_FILE_CONTENTS_TOOL = "get_file_contents"
LIST_PULL_REQUESTS_TOOL = "list_pull_requests"
CREATE_PULL_REQUEST_TOOL = "create_pull_request"

BRANCHES_PER_PAGE = 100
STATE_VERSION = 1

EXCLUDE_DIRS = {
    "node_modules", ".next", ".venv", "__pycache__",
    ".data", ".localstorage", ".git", ".verify",
}
EXCLUDE_FILES = {".env", ".env.local"}


def fail(message: str) -> "NoReturn":
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)


def parse_args():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repo-url", required=True)
    p.add_argument("--target-branch", required=True)
    p.add_argument("--source-dir", required=True)
    p.add_argument("--mcp-server-name", default="bifrost")
    p.add_argument("--tool-prefix", default="github-")
    p.add_argument("--app-name", default=None)
    p.add_argument("--deploy-branch-name", default=None)
    p.add_argument("--target-subdir", default="")
    p.add_argument("--commit-message", default=None)
    p.add_argument("--qa-status", default="unknown",
                    choices=["passed", "failed", "skipped", "unknown"])
    p.add_argument("--repo-visibility", default="private", choices=["private", "public"])
    p.add_argument("--state-dir", default=None,
                   help="where deploy state is kept (default: <parent of --source-dir>/.uab-deploy)")
    p.add_argument("--no-pr", action="store_true",
                   help="push only; don't open or look up a pull request")
    p.add_argument("--adopt-branch", action="store_true",
                   help="accept an existing deploy branch this sandbox has no record of pushing")
    p.add_argument("--sync", action="store_true",
                   help="restore/refresh --source-dir FROM GitHub (open deploy branch, else the "
                        "target branch) instead of pushing; local files that differ are backed up")
    p.add_argument("--sync-from", default=None,
                   help="with --sync: restore from this branch instead of choosing automatically")
    return p.parse_args()


def slugify(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    return slug


def parse_owner_repo(repo_url: str):
    if not repo_url.startswith("https://"):
        fail(f"--repo-url must be an https:// URL (got: '{repo_url}')")
    path = urlparse(repo_url).path.strip("/")
    if path.endswith(".git"):
        path = path[:-4]
    parts = path.split("/")
    if len(parts) < 2 or not parts[-1] or not parts[-2]:
        fail(f"could not parse owner/repo out of --repo-url '{repo_url}'")
    return parts[-2], parts[-1]


def validate_source_dir(source_dir: str):
    if not os.path.isdir(source_dir):
        fail(f"--source-dir '{source_dir}' does not exist or is not a directory")
    markers = ("PLAN.md", "package.json", "requirements.txt", "pyproject.toml")
    if not any(os.path.isfile(os.path.join(source_dir, m)) for m in markers):
        fail(
            f"--source-dir '{source_dir}' doesn't look like a generated app root "
            f"(no {', '.join(markers)} found)"
        )


def collect_files(source_dir: str, target_subdir: str):
    """
    Mirrors uab-app-creator-nobrand/scripts/package-app-fast.sh's python
    zipfile fallback walk -- same exclude list, kept as its own copy here
    per the same "stays self-contained" precedent used elsewhere in this
    skill family. Keep both lists in sync if either changes.

    The push tool only carries UTF-8 text, so any file that isn't valid
    UTF-8 (or contains a NUL byte) is returned in `skipped_binary` instead
    of being pushed. `blobs` maps each pushed path to its git blob SHA -- the
    same fingerprint GitHub reports -- for the divergence check and state.
    """
    files, skipped_binary, blobs = [], [], {}
    for root, dirs, names in os.walk(source_dir):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for name in names:
            if name in EXCLUDE_FILES:
                continue
            abs_path = os.path.join(root, name)
            rel_path = os.path.relpath(abs_path, source_dir).replace(os.sep, "/")
            if target_subdir:
                rel_path = f"{target_subdir.strip('/')}/{rel_path}"
            with open(abs_path, "rb") as f:
                data = f.read()
            if b"\x00" in data:
                skipped_binary.append(rel_path)
                continue
            try:
                content = data.decode("utf-8")
            except UnicodeDecodeError:
                skipped_binary.append(rel_path)
                continue
            files.append({"path": rel_path, "content": content})
            blobs[rel_path] = git_blob_sha(data)
    return files, sorted(skipped_binary), blobs


def git_blob_sha(data: bytes) -> str:
    """Git's object id for file content -- what GitHub lists as a file's `sha`."""
    return hashlib.sha1(b"blob %d\x00" % len(data) + data).hexdigest()


# --- deploy state -------------------------------------------------------------
# A small JSON record of what this sandbox last pushed, kept OUTSIDE the app
# folder (never pushed, never zipped). It's how a later deploy knows which
# branch/PR it owns and whether anyone else has changed those files since.

def state_file(state_dir: str, owner: str, repo: str, app_slug: str) -> str:
    return os.path.join(state_dir, f"{owner}__{repo}__{app_slug}.json")


def load_state(path: str):
    try:
        with open(path, encoding="utf-8") as f:
            state = json.load(f)
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as exc:
        print(f"warning: ignoring unreadable deploy state {path} ({exc})")
        return None
    return state if state.get("version") == STATE_VERSION else None


def save_state(path: str, state: dict):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


class McpError(Exception):
    def __init__(self, message: str, kind: str):
        super().__init__(message)
        # "not_configured" | "permission" | "tool_not_found" | "tool_error" | "transient"
        self.kind = kind


class DeployStop(Exception):
    """A deliberate stop before pushing (e.g. BRANCH_DIVERGED) -- nothing was changed."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


def _maybe_json(text: str):
    try:
        return json.loads(text)
    except (TypeError, ValueError):
        return text


def _text_of_block(block):
    """The text of an MCP text content block (pydantic TextContent or dict), else None."""
    if isinstance(block, dict):
        return block.get("text") if block.get("type") == "text" else None
    if getattr(block, "type", None) == "text":
        return getattr(block, "text", None)
    return None


def payload(result):
    """
    Normalizes whatever call_tool returns into plain Python data. In Code
    Mode, JSON results arrive already parsed and everything else (including
    tool errors) as a list of TextContent objects -- see caveat 4 in the
    module docstring. Structured-content and CallToolResult shapes are
    handled too.
    """
    if isinstance(result, (int, float, bool)) or result is None:
        return result
    if isinstance(result, list):
        texts = [_text_of_block(c) for c in result]
        if result and all(t is not None for t in texts):
            return _maybe_json("".join(texts))
        return result  # already-parsed data, e.g. [{name, sha}, ...]
    if isinstance(result, str):
        return _maybe_json(result)
    bare = _text_of_block(result)
    if bare is not None:
        return _maybe_json(bare)
    if isinstance(result, dict):
        if result.get("structuredContent") is not None:
            return result["structuredContent"]
        if isinstance(result.get("content"), list):
            texts = [c.get("text", "") for c in result["content"] if isinstance(c, dict)]
            return _maybe_json("".join(texts))
        return result
    structured = getattr(result, "structuredContent", None)
    if structured is not None:
        return structured
    content = getattr(result, "content", None)
    if isinstance(content, list):
        return _maybe_json("".join(getattr(c, "text", "") or "" for c in content))
    return result


def _is_error_result(result) -> bool:
    if isinstance(result, dict):
        return bool(result.get("isError"))
    return bool(getattr(result, "isError", False))


def classify(text: str) -> str:
    text = text.lower()
    # Bifrost / MCP: "tool 'github-push_files' not found" (JSON-RPC -32602)
    if re.search(r"tool '[^']*' not found", text) or "unknown tool" in text:
        return "tool_not_found"
    if "no such server" in text or "not configured" in text or "server not found" in text:
        return "not_configured"
    if (re.search(r"\b40[13] (unauthorized|forbidden)\b", text)
            or any(w in text for w in ("permission denied", "forbidden", "unauthorized",
                                       "insufficient scope", "missing scope"))):
        return "permission"
    return "transient"


# GitHub MCP server errors come back as text, e.g.
#   "failed to list branches: GET https://api.github.com/...: 404 Not Found []"
_GITHUB_ERROR_TEXT = re.compile(r"^failed to |: [45]\d\d [A-Z]", re.IGNORECASE)


def _error_text(data):
    """The error message if a normalized tool result is error text, else None."""
    if not isinstance(data, str):
        return None
    if _GITHUB_ERROR_TEXT.search(data) or classify(data) in ("tool_not_found", "not_configured"):
        return data
    return None


class GitHubTools:
    """
    Calls the GitHub MCP tools through one connector, resolving each tool's
    actual name once: f"{prefix}{name}" (gateway, e.g. github-push_files)
    first, then the bare name (direct GitHub connector).
    """

    def __init__(self, server_name: str, prefix: str):
        self.server_name = server_name
        self.prefix = prefix
        self.resolved = {}

    async def _raw_call(self, tool: str, body: dict):
        try:
            from mcp_client import call_tool
        except ImportError as exc:
            raise McpError(
                f"mcp_client is not importable in this sandbox ({exc}) -- Code Mode may not "
                "be enabled for this agent, or this file isn't being executed the way Code "
                "Mode expects. See references/mcp-mechanism.md caveat 3.",
                kind="not_configured",
            )

        try:
            result = await call_tool(self.server_name, tool, body=body)
        except Exception as exc:  # noqa: BLE001 -- errors normally arrive as text, see caveat 4
            kind = classify(str(exc))
            if kind == "transient" and _GITHUB_ERROR_TEXT.search(str(exc)):
                kind = "tool_error"  # a real GitHub answer (404/422...), not worth retrying
            if kind == "not_configured":
                raise McpError(f"MCP server '{self.server_name}' unavailable: {exc}", kind=kind)
            raise McpError(f"{tool} call failed: {exc}", kind=kind)

        # A tool can also answer with an error instead of raising -- flagged
        # (isError) or, as Code Mode does, just as error text (e.g. GitHub's
        # 404 / 422). That's a real answer, not a transient failure -- never
        # retried.
        data = payload(result)
        error = str(data) if _is_error_result(result) else _error_text(data)
        if error is not None:
            kind = classify(error)
            raise McpError(f"{tool} returned an error: {error}",
                           kind="tool_error" if kind == "transient" else kind)
        return data

    async def call(self, name: str, body: dict):
        if name in self.resolved:
            return await self._raw_call(self.resolved[name], body)
        candidates = [f"{self.prefix}{name}", name] if self.prefix else [name]
        last_exc = None
        for tool in candidates:
            try:
                result = await self._raw_call(tool, body)
            except McpError as exc:
                if exc.kind == "tool_not_found":
                    last_exc = exc
                    continue
                self.resolved[name] = tool
                raise
            self.resolved[name] = tool
            return result
        raise McpError(
            f"no tool named {' or '.join(repr(c) for c in candidates)} on MCP server "
            f"'{self.server_name}' -- check --mcp-server-name / --tool-prefix and the "
            f"gateway's tool allowlist ({last_exc})",
            kind="tool_not_found",
        )

    async def call_with_retries(self, name: str, body: dict, attempts: int = 3):
        last_exc = None
        for attempt in range(1, attempts + 1):
            try:
                return await self.call(name, body)
            except McpError as exc:
                if exc.kind != "transient":
                    raise  # only transient failures are worth retrying
                last_exc = exc
                if attempt < attempts:
                    print(f"attempt {attempt} looked transient ({exc}), retrying...")
                    await asyncio.sleep(3)
        raise last_exc


def _is_not_found(exc: McpError) -> bool:
    text = str(exc).lower()
    return exc.kind == "tool_error" and ("not found" in text or "404" in text)


async def authenticated_login(gh: GitHubTools) -> str:
    me = await gh.call_with_retries(GET_ME_TOOL, {})
    login = me.get("login") if isinstance(me, dict) else None
    if not login:
        raise McpError(f"{GET_ME_TOOL} did not return a login (got: {str(me)[:200]})", kind="tool_error")
    return login


async def list_branch_shas(gh: GitHubTools, owner: str, repo: str):
    """
    Returns {branch_name: sha} for every branch, or None if the repo itself
    doesn't exist. There is no get_branch tool -- this pages through
    list_branches instead.
    """
    shas, page = {}, 1
    while True:
        try:
            result = await gh.call_with_retries(LIST_BRANCHES_TOOL, {
                "owner": owner, "repo": repo, "page": page, "perPage": BRANCHES_PER_PAGE,
            })
        except McpError as exc:
            if page == 1 and _is_not_found(exc):
                return None
            raise
        branches = result.get("branches", []) if isinstance(result, dict) else (result or [])
        if not isinstance(branches, list):
            raise McpError(f"unexpected {LIST_BRANCHES_TOOL} result: {str(result)[:200]}", kind="tool_error")
        for b in branches:
            commit = b.get("commit") or {}
            shas[b.get("name")] = commit.get("sha") or b.get("sha")
        if len(branches) < BRANCHES_PER_PAGE:
            return shas
        page += 1


async def ensure_repo_exists(gh: GitHubTools, owner: str, repo: str, visibility: str):
    """
    Returns (repo_created, branch_shas). Checks for the repo with
    list_branches first, so creation never depends on how an "already
    exists" error happens to be worded.
    """
    branches = await list_branch_shas(gh, owner, repo)
    if branches is not None:
        print(f"repository {owner}/{repo} already exists — continuing")
        return False, branches

    login = await authenticated_login(gh)
    body = {"name": repo, "private": visibility == "private", "autoInit": True}
    if owner.lower() != login.lower():
        body["organization"] = owner  # create_repository has no `owner`; org repos use this
    try:
        await gh.call_with_retries(CREATE_REPOSITORY_TOOL, body)
        print(f"created new repository {owner}/{repo} ({visibility})")
        created = True
    except McpError as exc:
        if "already exists" not in str(exc).lower():
            raise
        print(f"repository {owner}/{repo} already exists — continuing")
        created = False

    # autoInit's first commit can take a moment to become visible
    for _ in range(5):
        branches = await list_branch_shas(gh, owner, repo)
        if branches:
            return created, branches
        await asyncio.sleep(2)
    fail(f"repository {owner}/{repo} has no branches after creation — autoInit may not "
         "have produced an initial commit")


async def create_branch(gh: GitHubTools, owner: str, repo: str, branch: str, from_branch: str):
    await gh.call_with_retries(CREATE_BRANCH_TOOL, {
        "owner": owner, "repo": repo, "branch": branch, "from_branch": from_branch,
    })
    print(f"created branch '{branch}' from '{from_branch}'")


async def list_dir(gh: GitHubTools, owner: str, repo: str, branch: str, path: str, fields):
    """One directory's entries on `branch` (JSON listings pass through the gateway)."""
    entries = await gh.call_with_retries(GET_FILE_CONTENTS_TOOL, {
        "owner": owner, "repo": repo, "path": path or "/",
        "ref": f"refs/heads/{branch}", "fields": fields,
    })
    if not isinstance(entries, list):
        raise McpError(f"expected a directory listing for '{path or '/'}' on {branch}, "
                       f"got: {str(entries)[:200]}", kind="tool_error")
    return entries


async def list_tree_entries(gh: GitHubTools, owner: str, repo: str, branch: str, root: str,
                            fields=("path", "type", "sha")):
    """
    Returns {path: entry} for every file under `root` on `branch`, walking
    directories with get_file_contents. (File *contents* can't come through
    the gateway -- Bifrost drops embedded resources, see mcp-mechanism.md --
    but directory listings, including each file's download_url, do.)
    An empty dict if `root` doesn't exist on that branch.
    """
    files, pending = {}, [root.strip("/")]
    while pending:
        path = pending.pop()
        try:
            entries = await list_dir(gh, owner, repo, branch, path, list(fields))
        except McpError as exc:
            if _is_not_found(exc) and path == root.strip("/"):
                return {}
            raise
        for e in entries:
            if e.get("type") == "dir":
                if os.path.basename(e["path"]) not in EXCLUDE_DIRS:
                    pending.append(e["path"])
            elif e.get("type") == "file":
                files[e["path"]] = e
    return files


async def list_tree(gh: GitHubTools, owner: str, repo: str, branch: str, root: str):
    """{path: blob_sha} for every file under `root` on `branch`."""
    entries = await list_tree_entries(gh, owner, repo, branch, root)
    return {path: e.get("sha") for path, e in entries.items()}


async def pull_requests_for(gh: GitHubTools, owner: str, repo: str, branch: str):
    """Every PR (open or closed) whose head is `branch`, newest first."""
    prs = await gh.call_with_retries(LIST_PULL_REQUESTS_TOOL, {
        "owner": owner, "repo": repo, "state": "all", "head": f"{owner}:{branch}", "perPage": 30,
    })
    if isinstance(prs, dict):
        prs = prs.get("pull_requests") or prs.get("items") or []
    if not isinstance(prs, list):
        raise McpError(f"unexpected {LIST_PULL_REQUESTS_TOOL} result: {str(prs)[:200]}", kind="tool_error")
    mine = []
    for pr in prs:
        head = pr.get("head")
        head_ref = head.get("ref") if isinstance(head, dict) else None
        if head_ref in (None, branch):
            mine.append(pr)
    return mine


def _is_merged(pr: dict) -> bool:
    return bool(pr.get("merged") or pr.get("merged_at"))


def find_conflicts(remote: dict, last_pushed: dict, local: dict):
    """
    Files someone else changed on GitHub since this sandbox last pushed them,
    that this push would overwrite (or resurrect). Local edits never count --
    only differences between GitHub and what we last pushed.
    """
    conflicts = []
    for path, pushed_sha in sorted(last_pushed.items()):
        if path not in local:
            continue  # we're not pushing it this time, so nothing gets overwritten
        remote_sha = remote.get(path)
        if remote_sha is None:
            conflicts.append(f"{path} (deleted on GitHub)")
        elif remote_sha != pushed_sha and remote_sha != local[path]:
            conflicts.append(f"{path} (changed on GitHub)")
    for path in sorted(set(local) & set(remote) - set(last_pushed)):
        if remote[path] != local[path]:
            conflicts.append(f"{path} (added on GitHub)")
    return conflicts


def pr_body(app_name: str, qa_status: str, skipped_binary, stale) -> str:
    lines = [f"Code for **{app_name}**, pushed by `uab-deploy` from the generation sandbox.", "",
             f"- QA status reported by the session: **{qa_status}**"]
    if qa_status != "passed":
        lines.append("  - Not confirmed to build, run, or pass QA in a real environment.")
    if skipped_binary:
        lines.append("- Binary files **not** pushed (the push tool carries text only) — add them "
                     "separately: " + ", ".join(f"`{p}`" for p in skipped_binary))
    if stale:
        lines.append("- Files on this branch that are **no longer in the app** (not deleted "
                     "automatically — remove them if that's intended): "
                     + ", ".join(f"`{p}`" for p in stale))
    lines += ["", "Merging this PR is the review step; nothing was hosted or deployed beyond this push."]
    return "\n".join(lines)


async def open_pull_request(gh: GitHubTools, owner: str, repo: str, branch: str, base: str,
                            title: str, body: str):
    pr = await gh.call_with_retries(CREATE_PULL_REQUEST_TOOL, {
        "owner": owner, "repo": repo, "title": title, "head": branch, "base": base, "body": body,
    })
    return pr if isinstance(pr, dict) else {}


# --- sync: restore the app FROM GitHub ------------------------------------------
# Used when a user comes back to an app: the sandbox may have been deleted
# (Nightona auto-deletes after ~5 days) or GitHub may have changes the sandbox
# doesn't (a reviewer's edit, a merge). File contents can't come through the
# gateway, so each file is downloaded from its download_url -- a raw.githubusercontent
# URL pinned to the commit, carrying a short-lived, single-file token for private
# repos. The token is never printed; the GitHub PAT never enters the sandbox.

class DownloadError(Exception):
    pass


def download(url: str, timeout: int = 60) -> bytes:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return r.read()
    except urllib.error.HTTPError as exc:
        raise DownloadError(f"HTTP {exc.code}") from None  # message only: the URL carries a token
    except (urllib.error.URLError, OSError, ValueError) as exc:
        raise DownloadError(type(exc).__name__ + ": " + str(getattr(exc, "reason", exc))[:120]) from None


def scan_local(source_dir: str, target_subdir: str):
    """{repo path: blob_sha} for every non-excluded local file (text and binary)."""
    found = {}
    if not os.path.isdir(source_dir):
        return found
    prefix = f"{target_subdir.strip('/')}/" if target_subdir.strip("/") else ""
    for root, dirs, names in os.walk(source_dir):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for name in names:
            if name in EXCLUDE_FILES:
                continue
            abs_path = os.path.join(root, name)
            rel = os.path.relpath(abs_path, source_dir).replace(os.sep, "/")
            with open(abs_path, "rb") as f:
                found[prefix + rel] = git_blob_sha(f.read())
    return found


LOGO_PATH = "public/uab-logo-white.png"  # where uab-branding GENERATE puts the UAB logo


def logo_missing(source_dir: str) -> bool:
    """True if the app's code references the UAB logo but the file isn't there."""
    if os.path.exists(os.path.join(source_dir, *LOGO_PATH.split("/"))):
        return False
    for root, dirs, names in os.walk(source_dir):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for name in names:
            if name.endswith((".tsx", ".ts", ".jsx", ".js")):
                with open(os.path.join(root, name), encoding="utf-8", errors="ignore") as f:
                    if "uab-logo-white.png" in f.read():
                        return True
    return False


async def choose_sync_source(gh, args, owner, repo, app_slug, branches, state):
    """The open deploy branch if there is one, else the target branch."""
    if args.sync_from:
        if args.sync_from not in branches:
            raise DeployStop("SYNC_SOURCE_MISSING", f"branch '{args.sync_from}' doesn't exist on {owner}/{repo}")
        return args.sync_from, args.deploy_branch_name or (state or {}).get("deploy_branch") or f"deploy/{app_slug}"
    candidate = args.deploy_branch_name or (state or {}).get("deploy_branch") or f"deploy/{app_slug}"
    if candidate in branches:
        try:
            prs = await pull_requests_for(gh, owner, repo, candidate)
        except McpError as exc:
            if exc.kind not in ("tool_not_found", "permission"):
                raise
            prs = None
        merged_without_open = prs is not None and any(_is_merged(p) for p in prs) \
            and not any(p.get("state") == "open" for p in prs)
        if not merged_without_open:
            return candidate, candidate  # its review is still in progress (or PRs can't be checked)
    return args.target_branch, candidate


async def run_sync(args) -> int:
    owner, repo = parse_owner_repo(args.repo_url)
    app_name = args.app_name or os.path.basename(os.path.normpath(args.source_dir))
    app_slug = slugify(app_name)
    if not app_slug:
        fail(f"could not derive a usable app slug from --app-name/--source-dir ('{app_name}')")
    root = args.target_subdir.strip("/")
    state_dir = args.state_dir or os.path.join(
        os.path.dirname(os.path.abspath(os.path.normpath(args.source_dir))), ".uab-deploy")
    state_path = state_file(state_dir, owner, repo, app_slug)
    state = load_state(state_path)
    gh = GitHubTools(args.mcp_server_name, args.tool_prefix)
    print(f"SYNC app: {app_name} (slug: {app_slug})  repo: {owner}/{repo}  into: {args.source_dir}  "
          f"connector: {args.mcp_server_name} (tool prefix '{args.tool_prefix}')")

    try:
        print("== SYNC 1: find what to restore from ==")
        branches = await list_branch_shas(gh, owner, repo)
        if branches is None:
            raise DeployStop("SYNC_REPO_MISSING", f"{owner}/{repo} doesn't exist (or isn't visible to "
                             "the GitHub connector) — nothing to restore")
        if args.target_branch not in branches:
            raise DeployStop("SYNC_SOURCE_MISSING", f"--target-branch '{args.target_branch}' doesn't "
                             f"exist on {owner}/{repo}")
        source, deploy_branch = await choose_sync_source(gh, args, owner, repo, app_slug, branches, state)
        print(f"SYNC_SOURCE: {source} ({'open deploy branch' if source == deploy_branch else 'target branch'})"
              f" at {(branches.get(source) or '?')[:12]}")

        print("== SYNC 2: list files on GitHub ==")
        fields = ["path", "type", "sha", "size", "download_url"]
        remote = await list_tree_entries(gh, owner, repo, source, root, fields)
        if not remote:
            raise DeployStop("SYNC_EMPTY", f"no files under '{root or '/'}' on {source}")
        print(f"{len(remote)} files on {source}")

        print("== SYNC 3: download changed and missing files ==")
        local = scan_local(args.source_dir, root)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        backup_dir = os.path.join(state_dir, f"sync-backup-{stamp}")
        added, updated, backed_up, unchanged = [], [], [], 0
        relisted = set()
        for path, entry in sorted(remote.items()):
            if local.get(path) == entry.get("sha"):
                unchanged += 1
                continue
            rel = path[len(root) + 1:] if root else path
            dest = os.path.join(args.source_dir, *rel.split("/"))
            try:
                data = download(entry.get("download_url") or "")
            except DownloadError as exc:
                folder = path.rsplit("/", 1)[0] if "/" in path else ""
                if folder in relisted:
                    raise DeployStop("SYNC_DOWNLOAD_FAILED", f"couldn't download {path} ({exc})")
                relisted.add(folder)  # links are short-lived: get fresh ones for this folder, once
                fresh = {e["path"]: e for e in await list_dir(gh, owner, repo, source, folder, fields)}
                try:
                    data = download((fresh.get(path) or {}).get("download_url") or "")
                except DownloadError as exc2:
                    raise DeployStop("SYNC_DOWNLOAD_FAILED", f"couldn't download {path} ({exc2})")
            if git_blob_sha(data) != entry.get("sha"):
                raise DeployStop("SYNC_DOWNLOAD_FAILED", f"{path}: downloaded content doesn't match "
                                 "GitHub's file (size/fingerprint mismatch)")
            if path in local:
                os.makedirs(os.path.dirname(os.path.join(backup_dir, *rel.split("/"))), exist_ok=True)
                shutil.copy2(dest, os.path.join(backup_dir, *rel.split("/")))
                backed_up.append(path)
                updated.append(path)
            else:
                added.append(path)
            os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
            with open(dest, "wb") as f:
                f.write(data)
        local_only = sorted(set(local) - set(remote))

        new_state = {
            "version": STATE_VERSION, "repo": f"{owner}/{repo}", "app_slug": app_slug,
            "deploy_branch": deploy_branch, "target_branch": args.target_branch,
            "target_subdir": root, "last_pushed_sha": branches.get(source),
            "files": {p: e.get("sha") for p, e in remote.items()},
            "pr": (state or {}).get("pr") if source == deploy_branch else None,
            "synced_from": source,
            "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
        save_state(state_path, new_state)

    except DeployStop as stop:
        print(f"FAIL: {stop.code} — {stop}", file=sys.stderr)
        return 1
    except McpError as exc:
        report_mcp_failure(exc)
        return 1

    print(f"added {len(added)}, updated {len(updated)}, unchanged {unchanged}")
    if backed_up:
        print(f"SYNC_BACKUP: {len(backed_up)} local file(s) differed from GitHub and were replaced; "
              f"the local versions are saved in {backup_dir}: {', '.join(backed_up)}")
    if local_only:
        print(f"LOCAL_ONLY: {len(local_only)} local file(s) aren't on GitHub (kept as-is): "
              f"{', '.join(local_only)}")
    if logo_missing(args.source_dir):
        print("MISSING_ASSET: public/uab-logo-white.png — the app references the UAB logo but it isn't "
              "on GitHub (the push tool can't carry binary files). Copy it from the uab-branding "
              "skill's assets/uabCoreLogoWhiteSmall.png.")
    print(f"recorded deploy state in {state_path}")
    print(f"SYNC_SUMMARY: repo={owner}/{repo} source={source} deploy_branch={deploy_branch} "
          f"files={len(remote)} added={len(added)} updated={len(updated)} unchanged={unchanged} "
          f"local_only={len(local_only)} backup={'yes' if backed_up else 'no'}")
    return 0


def report_mcp_failure(exc: McpError):
    if exc.kind == "not_configured":
        print(f"FAIL: MCP_CONNECTOR_NOT_CONFIGURED — {exc}", file=sys.stderr)
    elif exc.kind == "permission":
        print(f"FAIL: MCP_PERMISSION_DENIED — {exc}", file=sys.stderr)
    elif exc.kind == "tool_not_found":
        print(f"FAIL: MCP_TOOL_NOT_FOUND — {exc}", file=sys.stderr)
    else:
        print(f"FAIL: {exc}", file=sys.stderr)


async def run() -> int:
    args = parse_args()
    if args.sync:
        return await run_sync(args)

    owner, repo = parse_owner_repo(args.repo_url)
    validate_source_dir(args.source_dir)

    app_name = args.app_name or os.path.basename(os.path.normpath(args.source_dir))
    app_slug = slugify(app_name)
    if not app_slug:
        fail(f"could not derive a usable app slug from --app-name/--source-dir ('{app_name}')")
    commit_message = args.commit_message or f"Deploy {app_name} from generation sandbox"
    state_dir = args.state_dir or os.path.join(
        os.path.dirname(os.path.abspath(os.path.normpath(args.source_dir))), ".uab-deploy")
    state_path = state_file(state_dir, owner, repo, app_slug)
    state = load_state(state_path)
    root = args.target_subdir.strip("/")
    gh = GitHubTools(args.mcp_server_name, args.tool_prefix)

    print(f"app: {app_name} (slug: {app_slug})  repo: {owner}/{repo}  "
          f"target-branch: {args.target_branch}  "
          f"connector: {args.mcp_server_name} (tool prefix '{args.tool_prefix}')  "
          f"previous deploy state: {'found' if state else 'none'}")

    stale, pr_url, pr_status = [], None, "skipped (--no-pr)" if args.no_pr else "none"
    try:
        print("== STEP 1: ensure repo exists ==")
        repo_created, branches = await ensure_repo_exists(gh, owner, repo, args.repo_visibility)

        print(f"== STEP 2: resolve {args.target_branch} ==")
        if args.target_branch not in branches:
            if not repo_created:
                fail(f"--target-branch '{args.target_branch}' does not exist on {owner}/{repo} "
                     "and this isn't a fresh repo — check the branch name")
            # Fresh repo's default branch name may not match --target-branch.
            default_branch = "main" if "main" in branches else next(iter(branches))
            await create_branch(gh, owner, repo, args.target_branch, default_branch)
        else:
            print(f"'{args.target_branch}' is at {(branches[args.target_branch] or '?')[:12]}")

        print("== STEP 3: choose the deploy branch ==")
        # One review cycle = one branch + one PR: reuse the branch while its PR
        # is open; once merged, start a fresh branch from the target.
        base_name = args.deploy_branch_name or f"deploy/{app_slug}"
        candidate = args.deploy_branch_name or (state or {}).get("deploy_branch") or base_name
        prs = None
        if not args.no_pr:
            try:
                prs = await pull_requests_for(gh, owner, repo, candidate)
            except McpError as exc:
                if exc.kind not in ("tool_not_found", "permission"):
                    raise
                print(f"warning: can't look up pull requests ({exc}) — continuing without PR handling")
        open_pr = next((p for p in prs or [] if p.get("state") == "open"), None)
        merged_pr = next((p for p in prs or [] if _is_merged(p)), None)
        if candidate in branches and open_pr is None and merged_pr is not None:
            deploy_branch = f"{base_name}-{datetime.now(timezone.utc):%Y%m%d-%H%M}"
            mode = "new-after-merge"
            print(f"'{candidate}' was already merged (PR #{merged_pr.get('number')}) — starting a "
                  f"new review branch '{deploy_branch}' from '{args.target_branch}'")
        elif candidate in branches:
            deploy_branch, mode = candidate, "reuse"
            print(f"deploy branch '{deploy_branch}' exists"
                  + (f" with open PR #{open_pr.get('number')}" if open_pr else "")
                  + " — adding a new commit to it")
        else:
            deploy_branch = candidate
            mode = "new-after-merge" if merged_pr is not None else "new"
            if merged_pr is not None and base_name not in branches:
                deploy_branch = base_name  # merged branch was auto-deleted: reuse the plain name
            print(f"deploy branch '{deploy_branch}' doesn't exist yet — will create it from "
                  f"'{args.target_branch}'")

        print(f"== STEP 4: collect files from {args.source_dir} ==")
        files, skipped_binary, local_blobs = collect_files(args.source_dir, args.target_subdir)
        if not files:
            fail(f"no text files found under --source-dir '{args.source_dir}' after applying "
                 "the exclude list")
        print(f"collected {len(files)} text files")
        if skipped_binary:
            print(f"SKIPPED_BINARY: {len(skipped_binary)} file(s) not pushed (the push tool "
                  f"only carries text): {', '.join(skipped_binary)}")
        local_paths = set(local_blobs) | set(skipped_binary)

        print("== STEP 5: check GitHub for changes made since the last push ==")
        # Never overwrite someone else's work: compare what's on GitHub with
        # what this sandbox last pushed (the state file). Our own local edits
        # are expected; only GitHub-side changes to files we'd push count.
        tracked_files = (state or {}).get("files", {})
        if mode == "reuse":
            remote = await list_tree(gh, owner, repo, deploy_branch, root)
            if state and state.get("deploy_branch") == deploy_branch:
                conflicts = find_conflicts(remote, tracked_files, local_blobs)
                if conflicts:
                    raise DeployStop("BRANCH_DIVERGED", (
                        f"'{deploy_branch}' was changed on GitHub since this sandbox last pushed it: "
                        f"{', '.join(conflicts)}. Nothing was pushed. Bring those changes into the "
                        "sandbox first (uab-deploy --sync), re-apply the edits, and deploy again."))
                stale_source = tracked_files
            else:
                differing = sorted(p for p in local_blobs if p in remote and remote[p] != local_blobs[p])
                if differing and not args.adopt_branch:
                    raise DeployStop("BRANCH_NOT_TRACKED", (
                        f"'{deploy_branch}' already exists, this sandbox has no record of pushing it, "
                        f"and {len(differing)} file(s) differ from it "
                        f"({', '.join(differing[:10])}{', ...' if len(differing) > 10 else ''}). "
                        "Nothing was pushed. Run uab-deploy --sync to start from the branch's "
                        "current content, or pass --adopt-branch if this sandbox's files should "
                        "replace them."))
                stale_source = remote
        elif state:  # a new review branch for an app this sandbox deployed before
            remote = await list_tree(gh, owner, repo, args.target_branch, root)
            conflicts = find_conflicts(remote, tracked_files, local_blobs)
            if conflicts:
                raise DeployStop("TARGET_CHANGED", (
                    f"'{args.target_branch}' has changes made since this app was last deployed: "
                    f"{', '.join(conflicts)}. Nothing was pushed. Bring them into the sandbox first "
                    "(uab-deploy --sync), re-apply the edits, and deploy again."))
            stale_source = tracked_files
        else:
            remote, stale_source = {}, {}
        print("no conflicting changes on GitHub" if remote or state else
              "first deploy of this app from this sandbox — nothing to compare")
        stale = sorted(p for p in remote if p not in local_paths and p in stale_source)
        if stale:
            print(f"STALE_ON_BRANCH: {len(stale)} file(s) on GitHub are no longer in the app "
                  f"(not deleted automatically): {', '.join(stale)}")

        print(f"== STEP 6: push to '{deploy_branch}' ==")
        if mode != "reuse":
            await create_branch(gh, owner, repo, deploy_branch, args.target_branch)
        await gh.call_with_retries(PUSH_FILES_TOOL, {
            "owner": owner,
            "repo": repo,
            "branch": deploy_branch,
            "files": files,
            "message": commit_message,
        })
        tip = ((await list_branch_shas(gh, owner, repo)) or {}).get(deploy_branch)
        new_state = {
            "version": STATE_VERSION, "repo": f"{owner}/{repo}", "app_slug": app_slug,
            "deploy_branch": deploy_branch, "target_branch": args.target_branch,
            "target_subdir": root, "last_pushed_sha": tip, "files": local_blobs,
            "pr": (state or {}).get("pr") if mode == "reuse" else None,
            "updated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
        save_state(state_path, new_state)
        print(f"pushed {len(files)} files; branch tip {(tip or '?')[:12]}; recorded deploy state "
              f"in {state_path}")

        print("== STEP 7: pull request ==")
        if args.no_pr:
            print("skipped (--no-pr)")
        elif prs is None:
            pr_status = "unavailable"
            print("skipped — pull request tools aren't available on this connector")
        elif mode == "reuse" and open_pr is not None:
            pr_url, pr_status = open_pr.get("html_url"), "existing"
        else:
            try:
                pr = await open_pull_request(
                    gh, owner, repo, deploy_branch, args.target_branch, commit_message,
                    pr_body(app_name, args.qa_status, skipped_binary, stale))
                pr_url, pr_status = pr.get("html_url"), "opened"
            except McpError as exc:
                pr_status = "not-opened"
                print(f"PR_NOT_OPENED: the push succeeded, but opening the pull request failed: {exc}")
        if pr_url:
            print(f"PR: {pr_url} ({pr_status})")
            new_state["pr"] = {"url": pr_url}
            save_state(state_path, new_state)

    except DeployStop as stop:
        print(f"FAIL: {stop.code} — {stop}", file=sys.stderr)
        return 1
    except McpError as exc:
        report_mcp_failure(exc)
        return 1

    print("== done ==")
    print(f"PASS: {deploy_branch} pushed to {owner}/{repo}")
    print(f"DEPLOY_SUMMARY: repo={owner}/{repo} deploy_branch={deploy_branch} "
          f"target_branch={args.target_branch} branch_mode={mode} "
          f"is_first_deploy={str(mode != 'reuse').lower()} "
          f"repo_created={str(repo_created).lower()} qa_status={args.qa_status} "
          f"skipped_binary={len(skipped_binary)} stale_on_branch={len(stale)} "
          f"pr={pr_status} pr_url={pr_url or 'none'}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
