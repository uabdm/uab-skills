# Environment Fallback Messaging

This skill never runs a git command — it just writes files to a folder and
packages them into a zip. This file covers what to tell the project leader
when the environment is missing something `scripts/verify-web-app.sh` /
`verify-worker-app.sh` or `scripts/package-app.sh` needs to do their job.

## If node/python isn't installed

If the runtime check in `verify-web-app.sh` / `verify-worker-app.sh` fails,
do not attempt to install it yourself — you don't know what permissions this
machine's user has, and a half-finished or failed install is worse than not
trying. Tell whoever is present, plainly, which one is missing, that they
(or whoever manages their computer) need to install it (Node.js from
nodejs.org, or Python from python.org), and that the alternative is to skip
installing anything: copy the IDEA.md template from the platform repo and
paste it into a plain chat AI tool instead, like claude.ai. That path
doesn't run anything on your computer at all — it will write out your plan
and your app's files as text for your IT team to build and run from there.

Do not proceed past this point until the runtime check genuinely succeeds —
never assume or claim it worked.

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
