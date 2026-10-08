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

STILL NEEDS VERIFICATION (see references/mcp-mechanism.md):
  3. Whether THIS FILE, checked in at scripts/deploy.py, can be executed
     directly in the sandbox and successfully `import mcp_client` --
     or whether Code Mode only exposes mcp_client to script *source* the
     agent passes inline to a Code-Mode-specific call. If it's the
     latter, SKILL.md must instruct the agent to read this file's
     contents and pass them as the script body instead of running the
     file directly -- the logic below is unchanged either way.
  4. The exact Python shape call_tool returns/raises. payload() and
     classify() below accept every shape seen in MCP results (structured
     content, JSON text content, plain strings, isError results) so this
     is defensive rather than blocking; tighten once confirmed.
"""
import argparse
import asyncio
import json
import os
import re
import sys
from urllib.parse import urlparse

# Bare tool names on the GitHub MCP server (verified 2026-10-08). Called as
# f"{--tool-prefix}{name}" first, falling back to the bare name.
CREATE_REPOSITORY_TOOL = "create_repository"
LIST_BRANCHES_TOOL = "list_branches"
CREATE_BRANCH_TOOL = "create_branch"
PUSH_FILES_TOOL = "push_files"
GET_ME_TOOL = "get_me"

BRANCHES_PER_PAGE = 100

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
    of being pushed.
    """
    files, skipped_binary = [], []
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
    return files, sorted(skipped_binary)


class McpError(Exception):
    def __init__(self, message: str, kind: str):
        super().__init__(message)
        # "not_configured" | "permission" | "tool_not_found" | "tool_error" | "transient"
        self.kind = kind


def _maybe_json(text: str):
    try:
        return json.loads(text)
    except (TypeError, ValueError):
        return text


def payload(result):
    """
    Normalizes whatever call_tool returns into plain Python data. MCP tool
    results arrive as structured content, as JSON inside text content
    blocks, or already parsed -- see caveat 4 in the module docstring.
    """
    if isinstance(result, (list, int, float, bool)) or result is None:
        return result
    if isinstance(result, str):
        return _maybe_json(result)
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
    if re.search(r"tool\b.*\bnot found", text) or "unknown tool" in text:
        return "tool_not_found"
    if "no such server" in text or "not configured" in text or "server not found" in text:
        return "not_configured"
    if any(w in text for w in ("permission", "forbidden", "403", "401", "unauthorized", "scope")):
        return "permission"
    return "transient"


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
        except Exception as exc:  # noqa: BLE001 -- real shape unconfirmed, see caveat 4
            kind = classify(str(exc))
            if kind == "not_configured":
                raise McpError(f"MCP server '{self.server_name}' unavailable: {exc}", kind=kind)
            raise McpError(f"{tool} call failed: {exc}", kind=kind)

        # A tool can also answer with an error result instead of raising
        # (e.g. GitHub's 404 / 422). That's a real answer, not a transient
        # failure -- never retried.
        if _is_error_result(result):
            text = str(payload(result))
            kind = classify(text)
            raise McpError(f"{tool} returned an error: {text}",
                           kind="tool_error" if kind == "transient" else kind)
        return payload(result)

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


async def run() -> int:
    args = parse_args()

    owner, repo = parse_owner_repo(args.repo_url)
    validate_source_dir(args.source_dir)

    app_name = args.app_name or os.path.basename(os.path.normpath(args.source_dir))
    app_slug = slugify(app_name)
    if not app_slug:
        fail(f"could not derive a usable app slug from --app-name/--source-dir ('{app_name}')")
    deploy_branch = args.deploy_branch_name or f"deploy/{app_slug}"
    commit_message = args.commit_message or f"Deploy {app_name} from generation sandbox"
    gh = GitHubTools(args.mcp_server_name, args.tool_prefix)

    print(f"app: {app_name} (slug: {app_slug})  repo: {owner}/{repo}  "
          f"target-branch: {args.target_branch}  deploy-branch: {deploy_branch}  "
          f"connector: {args.mcp_server_name} (tool prefix '{args.tool_prefix}')")

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

        print("== STEP 3: resolve/create deploy branch ==")
        is_first_deploy = deploy_branch not in branches
        if is_first_deploy:
            await create_branch(gh, owner, repo, deploy_branch, args.target_branch)
        else:
            print(f"deploy branch '{deploy_branch}' already exists — adding a new commit to it")

        print(f"== STEP 4: collect files from {args.source_dir} ==")
        files, skipped_binary = collect_files(args.source_dir, args.target_subdir)
        if not files:
            fail(f"no text files found under --source-dir '{args.source_dir}' after applying "
                 "the exclude list")
        print(f"collected {len(files)} text files")
        if skipped_binary:
            print(f"SKIPPED_BINARY: {len(skipped_binary)} file(s) not pushed (the push tool "
                  f"only carries text): {', '.join(skipped_binary)}")

        print("== STEP 5: push ==")
        await gh.call_with_retries(PUSH_FILES_TOOL, {
            "owner": owner,
            "repo": repo,
            "branch": deploy_branch,
            "files": files,
            "message": commit_message,
        })

    except McpError as exc:
        if exc.kind == "not_configured":
            print(f"FAIL: MCP_CONNECTOR_NOT_CONFIGURED — {exc}", file=sys.stderr)
        elif exc.kind == "permission":
            print(f"FAIL: MCP_PERMISSION_DENIED — {exc}", file=sys.stderr)
        elif exc.kind == "tool_not_found":
            print(f"FAIL: MCP_TOOL_NOT_FOUND — {exc}", file=sys.stderr)
        else:
            print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    print("== done ==")
    print(f"PASS: {deploy_branch} pushed to {owner}/{repo}")
    print(f"DEPLOY_SUMMARY: repo={owner}/{repo} deploy_branch={deploy_branch} "
          f"target_branch={args.target_branch} is_first_deploy={str(is_first_deploy).lower()} "
          f"repo_created={str(repo_created).lower()} qa_status={args.qa_status} "
          f"skipped_binary={len(skipped_binary)}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
