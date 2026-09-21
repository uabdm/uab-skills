# Environment Fallback Messaging

This skill never runs a git command — it just writes files to a folder and
packages them into a zip. This file covers what to tell the project leader
when the environment is missing something `scripts/verify-web-app.sh` /
`verify-worker-app.sh` or `scripts/package-app.sh` needs to do their job.

## If node/python isn't installed

`scripts/preflight-check.sh` runs the runtime check for both
`verify-web-app.sh` / `verify-worker-app.sh` and, as of step a2 in
`SKILL.md`, before generation even starts. If it fails, do not attempt to
install anything yourself — you don't know what permissions this machine's
user has, and a half-finished or failed install is worse than not trying.
Tell whoever is present, plainly, which one is missing, that they (or
whoever manages their computer) need to install it (Node.js from
nodejs.org, or Python from python.org), and that the alternative is to skip
installing anything: copy the IDEA.md template from the platform repo and
paste it into a plain chat AI tool instead, like claude.ai. That path
doesn't run anything on your computer at all — it will write out your plan
and your app's files as text for your IT team to build and run from there.

Do not proceed past this point until the preflight check genuinely
succeeds — never assume or claim it worked.

### If this is a sandbox environment (Daytona, TrueForge, or similar)

`preflight-check.sh` treats an ephemeral automation sandbox (a container
spun up specifically to run this generation task) differently from a
person's own machine, because there's no one present in a sandbox pipeline
to act on "please go install Node.js yourself" the way a project leader
can. It detects this via `is_ephemeral_sandbox()` — env vars matching
`DAYTONA_*`/`CODESPACE_*`/`GITPOD_*`/`CODESANDBOX_*`/`E2B_*`, `/.dockerenv`,
or a container-flavored `/proc/1/cgroup` — and, only when one of those
fires, attempts to install Node.js itself from Node's own official binary
release (checksum-verified against nodejs.org's published
`SHASUMS256.txt`, never a third-party script) before giving up. Node/npm
installed this way are also symlinked into `/usr/local/bin` so every later
shell command in the same sandbox session finds them too, not just the
process that ran the install — this matters because most agent harnesses
run each shell command in its own fresh process with no inherited
environment, so a plain `export PATH=` inside `preflight-check.sh` alone
would never have reached a later, separate `npm install` call.

If `preflight-check.sh` still fails after that, the report tells you which
of these you hit and what to do about each:

- **The self-install itself failed.** The report's `WARN:` lines say why —
  almost always nodejs.org being unreachable from that sandbox's network,
  or an unsupported OS/architecture (only Linux x64/arm64 is supported;
  Python has no equivalent official portable tarball, so a worker app in a
  sandbox without `apt-get`+root for Python falls straight to this). This
  is a platform/network-config problem for whoever manages the sandbox's
  egress rules — not something a re-run fixes.
- **This platform's sandbox wasn't detected as one at all.** If Node/npm
  work fine in an interactive terminal on the same sandbox but
  `preflight-check.sh` still reported it as a "person's own machine" (no
  self-install attempted), the env-var heuristic above didn't match this
  particular platform. Two things to do: (1) re-run with
  `UAB_FORCE_SANDBOX=1` set to force the self-install path immediately, and
  (2) find out what this platform actually injects — run `env | sort` in
  that same sandbox and look for anything platform-specific (its own name,
  a workspace/session ID) — so the detection list above can be extended to
  recognize it automatically next time.
- **Registry/network unreachable but Node itself is fine.**
  `preflight-check.sh` also probes `registry.npmjs.org` / `pypi.org`
  directly, separate from the binary-presence/install check — a sandbox
  can have a perfectly working Node/npm and still fail every install
  because of an egress allowlist or missing proxy config. This is a
  network/platform-config fix, not a Node-install problem, and self-install
  can't do anything about it.

### If a command times out mid-verify (e.g. "command execution timeout" on `npm run build`)

This is the sandbox harness's OWN per-command wall-clock limit killing the
shell call, not `npm`/`next` reporting a build failure — a cold Next.js
production build (type-check + lint + compile) commonly takes 1-5 minutes,
and some sandboxes (confirmed on TrueForge's Daytona-backed sandbox)
enforce a ceiling well under that. The fix is `scripts/bg-run.sh` /
`scripts/bg-status.sh` (see `SKILL.md`'s Verify step) — run the slow
command detached and poll it in small, cheap, separate calls instead of
one call that has to finish inside the timeout window. Do not: retry the
same blocking call hoping it's faster this time, run steps "manually" to
dodge the timeout without backgrounding them, or guess that a build
probably succeeded because it got partway through before being killed.

If none of `preflight-check.sh`'s own `WARN:`/report lines are visible to
you — only a paraphrased "Node.js is not installed" summary — that's this
skill's plain-language persona (see `SKILL.md`) hiding the technical detail
from what it assumes is a non-technical project leader. If you're
debugging the pipeline itself rather than acting as that project leader,
ask directly for the script's raw, unparaphrased stdout, or run
`scripts/preflight-check.sh web` (or `worker`) yourself in a raw terminal
into the sandbox if the platform exposes one.

## If no archiving tool is available for packaging

`scripts/package-app.sh` tries `zip`, then PowerShell's `Compress-Archive`,
then Python's `zipfile` module, in that order. If none is available, it
fails with a clear message rather than producing a partial zip. Tell the
project leader plainly: the app itself is fully built and verified in its
project folder, but this machine couldn't create the zip file — whoever
picks up the folder next can zip it themselves, or they can install any one
of `zip`, PowerShell, or Python and re-run `scripts/package-app.sh`.

## What running this skill assumes about the environment

This skill assumes it's running somewhere that can execute commands (Claude
Code or an equivalent tool), on a machine that already has (or can get)
Node.js or Python, whichever the app type needs. That's the whole point of
the skill format over IDEA.md's raw copy-paste path — it gets real local
verification (the app actually installs, builds, and serves) before
anything is handed back. This machine doesn't have to belong to the project
leader personally — it's just as likely to be a technical teammate's or
their IT contact's, running the skill on the project leader's behalf after
the interview.

If someone truly has nothing installed anywhere and wants a zero-tooling
path, that's what `IDEA.md` itself is for (paste it into claude.ai directly)
— point them there instead of trying to force this skill's script-based flow
onto an environment that can't run commands at all.
