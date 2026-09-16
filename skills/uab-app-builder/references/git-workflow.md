# Git & Environment Fallback Messaging

The mechanical git steps live in `scripts/setup-develop-branch.sh` and
`scripts/push-to-develop.sh`. This file covers what to tell the project
leader when the environment can't run them, and why the `develop`-branch
requirement exists at all.

## Why `develop` first

Generated apps use three branches — `develop`, `qa`, `production` (see
`pipelines-azure-devops.md`) — and the very first push after generation is
what provisions real Azure resources. That first push must land on
`develop`, never on `production` — a brand-new local folder or a freshly
cloned Azure Repos repo starts with only one branch, and if files are
written while sitting on it and the project leader later pushes as-is,
whatever Azure resources get created first will carry the Production label
and URL. `scripts/setup-develop-branch.sh` gets onto `develop` before that
can happen, and it does so non-destructively — a local rename
(`git branch -m develop`) never touches or deletes anything on the remote.

## If git isn't installed

Run `scripts/setup-develop-branch.sh` before generating any scaffold files.
If it exits non-zero because `git --version` fails, do NOT attempt to
install git yourself under any circumstances — you don't know what
permissions this machine's user has, and a half-finished or failed install
is worse than not trying. Tell whoever is present, plainly:

> "This step needs git installed, which I don't see on this machine. You
> have two options: (1) ask whoever manages your computer to install Git
> (search 'Git for Windows' or 'Git for Mac' — it's a standard, free tool),
> then start over here, or (2) skip installing anything: copy the IDEA.md
> template from the platform repo and paste it into a plain chat AI tool
> instead, like claude.ai. That path doesn't run anything on your computer
> at all — it will write out your plan and your app's files as text, and
> your IT team can build and deploy it from there."

Do not proceed past this point until `git --version` genuinely succeeds —
never assume or claim it worked.

## If node/python isn't installed

Same reasoning applies in `scripts/verify-web-app.sh` /
`verify-worker-app.sh`: if the runtime check fails, do not attempt to
install it. Tell whoever is present which one is missing, that they (or
whoever manages their computer) need to install it (Node.js from nodejs.org,
or Python from python.org), and that the alternative is the same
paste-into-claude.ai fallback described above.

## If there's no git remote configured yet

`scripts/push-to-develop.sh` checks for a remote before attempting to push.
If none is configured — a plain local folder with nothing to push to yet —
it skips pushing entirely and reports that. Say so plainly in the final
message to the project leader: their IT team needs to connect this folder
to an Azure Repos repository and push the `develop` branch themselves. Never
invent or guess a remote URL.

## What running this skill assumes about the environment

This skill assumes it's running somewhere that can execute commands (Claude
Code or an equivalent tool), on a machine that already has (or can get) git
and Node.js/Python. That's the whole point of the skill format over IDEA.md's
raw copy-paste path — it gets local verification, a real push to `develop`,
and the Development pipeline deploying automatically. This machine doesn't
have to belong to the project leader personally — it's just as likely to be
a technical teammate's or their IT contact's, running the skill on the
project leader's behalf after the interview.

If someone truly has nothing installed anywhere and wants a zero-tooling
path, that's what `IDEA.md` itself is for (paste it into claude.ai directly)
— point them there instead of trying to force this skill's script-based flow
onto an environment that can't run commands at all.
