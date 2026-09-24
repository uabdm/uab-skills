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

NEEDS VERIFICATION before this is trusted in production (see
references/mcp-mechanism.md for the full list) -- most importantly:

  1. Exact tool names on the actual configured GitHub MCP connector.
     CREATE_REPOSITORY_TOOL / CREATE_BRANCH_TOOL / PUSH_FILES_TOOL /
     GET_BRANCH_TOOL below are the commonly-documented names on the
     official github/github-mcp-server, NOT yet confirmed against a live
     TrueForge connector. Confirm with Code Mode's `get_tool_output_schema`
     before relying on this.
  2. Whether the push tool accepts binary content (base64 + an encoding
     field) or text/UTF-8 only.
  3. Whether THIS FILE, checked in at scripts/deploy.py, can be executed
     directly in the sandbox and successfully `import mcp_client` --
     or whether Code Mode only exposes mcp_client to script *source* the
     agent passes inline to a Code-Mode-specific call. If it's the
     latter, SKILL.md must instruct the agent to read this file's
     contents and pass them as the script body instead of running the
     file directly -- the logic below is unchanged either way.
  4. The exact error surface call_tool raises/returns on failure.
  5. Whether "repository already exists" is distinguishable from other
     permission-shaped failures on CREATE_REPOSITORY_TOOL.
"""
import argparse
import asyncio
import base64
import os
import re
import sys
from urllib.parse import urlparse

# See caveat 1 above -- confirm against the live connector before trusting these.
CREATE_REPOSITORY_TOOL = "create_repository"
GET_BRANCH_TOOL = "get_branch"
CREATE_BRANCH_TOOL = "create_branch"
PUSH_FILES_TOOL = "push_files"

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
    p.add_argument("--mcp-server-name", default="github")
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
    """
    files = []
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
                content_b64 = base64.b64encode(f.read()).decode("ascii")
            files.append({"path": rel_path, "content": content_b64, "encoding": "base64"})
    return files


class McpError(Exception):
    def __init__(self, message: str, kind: str):
        super().__init__(message)
        self.kind = kind  # "not_configured" | "permission" | "transient" | "other"


async def call(server_name: str, tool: str, body: dict):
    """
    Thin wrapper around Code Mode's bridged MCP call. Classifies failures
    by inspecting whatever call_tool actually raises/returns -- see caveat
    4 in the module docstring; this classification is best-effort until
    verified against a live connector.
    """
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
        result = await call_tool(server_name, tool, body=body)
    except Exception as exc:  # noqa: BLE001 -- real shape unconfirmed, see caveat 4
        text = str(exc).lower()
        if "not found" in text or "not configured" in text or "no such server" in text:
            raise McpError(f"MCP server '{server_name}' unavailable: {exc}", kind="not_configured")
        if "permission" in text or "forbidden" in text or "403" in text or "scope" in text:
            raise McpError(f"{tool} rejected on permissions: {exc}", kind="permission")
        raise McpError(f"{tool} call failed: {exc}", kind="transient")

    return result


async def call_with_retries(server_name: str, tool: str, body: dict, attempts: int = 3):
    last_exc = None
    for attempt in range(1, attempts + 1):
        try:
            return await call(server_name, tool, body)
        except McpError as exc:
            if exc.kind in ("not_configured", "permission"):
                raise  # never retry these
            last_exc = exc
            if attempt < attempts:
                print(f"attempt {attempt} looked transient ({exc}), retrying...")
                await asyncio.sleep(3)
    raise last_exc


async def ensure_repo_exists(server: str, owner: str, repo: str, visibility: str) -> bool:
    """Returns True if this call actually created a new repo."""
    try:
        await call_with_retries(server, CREATE_REPOSITORY_TOOL, {
            "owner": owner,
            "name": repo,
            "private": visibility == "private",
            "auto_init": True,
        })
        print(f"created new repository {owner}/{repo} ({visibility})")
        return True
    except McpError as exc:
        text = str(exc).lower()
        if "already exists" in text:
            print(f"repository {owner}/{repo} already exists — continuing")
            return False
        raise


async def get_branch_sha(server: str, owner: str, repo: str, branch: str):
    try:
        result = await call(server, GET_BRANCH_TOOL, {"owner": owner, "repo": repo, "branch": branch})
    except McpError as exc:
        if "not found" in str(exc).lower():
            return None
        raise
    return result.get("sha") or result.get("commit", {}).get("sha")


async def ensure_branch(server: str, owner: str, repo: str, branch: str, base_sha: str):
    sha = await get_branch_sha(server, owner, repo, branch)
    if sha:
        return sha
    await call_with_retries(server, CREATE_BRANCH_TOOL, {
        "owner": owner, "repo": repo, "branch": branch, "sha": base_sha,
    })
    print(f"created branch '{branch}' from {base_sha[:12]}")
    return base_sha


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

    print(f"app: {app_name} (slug: {app_slug})  repo: {owner}/{repo}  "
          f"target-branch: {args.target_branch}  deploy-branch: {deploy_branch}")

    try:
        print("== STEP 1: ensure repo exists ==")
        repo_created = await ensure_repo_exists(args.mcp_server_name, owner, repo, args.repo_visibility)

        print(f"== STEP 2: resolve {args.target_branch}'s tip ==")
        target_sha = await get_branch_sha(args.mcp_server_name, owner, repo, args.target_branch)
        if target_sha is None:
            if not repo_created:
                fail(f"--target-branch '{args.target_branch}' does not exist on {owner}/{repo} "
                     "and this isn't a fresh repo — check the branch name")
            # Fresh repo's default branch name may not match --target-branch.
            default_sha = await get_branch_sha(args.mcp_server_name, owner, repo, "main")
            if default_sha is None:
                fail(f"could not resolve a base commit for the newly created repo {owner}/{repo} "
                     "(tried --target-branch and 'main') — auto_init may not have produced a commit")
            target_sha = await ensure_branch(args.mcp_server_name, owner, repo, args.target_branch, default_sha)

        print("== STEP 3: resolve/create deploy branch ==")
        is_first_deploy = (await get_branch_sha(args.mcp_server_name, owner, repo, deploy_branch)) is None
        await ensure_branch(args.mcp_server_name, owner, repo, deploy_branch, target_sha)

        print(f"== STEP 4: collect files from {args.source_dir} ==")
        files = collect_files(args.source_dir, args.target_subdir)
        if not files:
            fail(f"no files found under --source-dir '{args.source_dir}' after applying the exclude list")
        print(f"collected {len(files)} files")

        print("== STEP 5: push ==")
        await call_with_retries(args.mcp_server_name, PUSH_FILES_TOOL, {
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
        else:
            print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    print("== done ==")
    print(f"PASS: {deploy_branch} pushed to {owner}/{repo}")
    print(f"DEPLOY_SUMMARY: repo={owner}/{repo} deploy_branch={deploy_branch} "
          f"target_branch={args.target_branch} is_first_deploy={str(is_first_deploy).lower()} "
          f"repo_created={str(repo_created).lower()} qa_status={args.qa_status}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(run()))
