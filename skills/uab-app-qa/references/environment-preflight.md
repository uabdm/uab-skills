# Environment preflight (Phase 0)

This skill is explicitly meant to run in environments `uab-app-creator`
never assumes: a person's own machine, a CI runner, a fresh unzipped
download, a container that's never had Node or Python installed on it.
Don't assume the sandbox you land in has `npm`/`node`/`python3` just
because a prior generation step ran somewhere else that did. Check first,
every time, before Phase 1 spends effort on a command that's about to fail
with "command not found."

## What to check

Run `scripts/check-and-install-tools.sh` (optionally pass `web` or
`worker` — it auto-detects from `package.json` /
`requirements.txt`/`pyproject.toml` if you don't). It:

1. Detects the app type the same way `SKILL.md`'s Scope detection does.
2. Checks for the tools that type actually needs: `node`+`npm` for a web
   app, `python3`+`pip3` for a worker.
3. If a tool is missing, attempts a best-effort install using whatever
   package manager is actually present (`apt-get`, `apk`, `dnf`, `yum`,
   `brew`, in that order) — with and without a `sudo` prefix, since some
   sandboxes run as root already and `sudo` itself may not exist.
4. Also checks for `zip`/`tar` (needed later if you end up packaging a
   handoff artifact per `references/timeout-fallback.md`) and attempts the
   same best-effort install if neither is present.
5. Reports a clear PASS/FAIL summary — which tools were already there,
   which were installed just now, and which couldn't be installed at all.

Treat a script failure here exactly like a script failure anywhere else in
this skill: read the actual output, don't just retry blindly.

## If a tool can't be installed

Some sandboxes genuinely don't allow installing anything (no `sudo`, no
network egress to a package registry, an unsupported/minimal base image).
That's a real environment limit, not something to loop on:

- **`node`/`npm` missing and can't be installed on a web app** — Phase 1
  (install) and everything after it (Phase 2 build, Phase 3 browser test)
  cannot run at all in this sandbox. Don't attempt them anyway and produce
  a misleading partial log. Say so plainly in the Phase 5 report, and go
  straight to `references/timeout-fallback.md`'s packaging step so the
  user still gets the app's source out of this environment rather than
  nothing.
- **`python3`/`pip3` missing on a worker app** — same logic, worker-shaped.
- **`zip`/`tar` both missing** — you can still report findings in text, but
  say explicitly that you couldn't produce a downloadable archive in this
  environment and that the app's files are only reachable by copying them
  out some other way (e.g. the harness's own file-read tools).

## Playwright's own system dependencies (Phase 3)

`npx playwright install chromium --with-deps` needs OS-level shared
libraries beyond what a bare `apt-get install nodejs npm` gives you, and
`--with-deps` itself shells out to the OS package manager — which hits the
exact same "no sudo / no network" wall described above. If that command
fails for a permissions/package-manager reason (not a network flake worth
retrying once), don't loop on it: treat Phase 3 as unavailable in this
sandbox, say so in the Phase 5 report, and don't let it block Phases 1–2,
which don't need a browser at all. This is a narrower, more specific case
of the same "check before you loop" principle as the rest of this file —
it just surfaces mid-way through Phase 3 instead of at the very start.

## Why this runs before Phase 1, not inside it

Keeping the tool check as its own step means a missing-tool failure and a
real dependency/build/runtime defect never get tangled up in the same log
— exactly the reason `references/dependency-audit.md` keeps Phase 1 itself
scoped to install+audit only. A `npm: command not found` is an environment
fact to report and route around (install it, or fall back), never a bug in
the app to "fix."
