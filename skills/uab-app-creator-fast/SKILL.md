---
name: uab-app-creator-fast
description: Fast, zero-verification counterpart to uab-app-creator — generates UAB app source code (same interview, same decision matrix, same Next.js+MUI or Python/FastAPI scaffolds, same UAB branding and Ory Hydra OIDC login pattern) but never runs npm/pip, never installs, audits, builds, or checks the code in any way — it just writes the files and zips them. Use ONLY when the user explicitly asks for something fast, a quick proof-of-concept, a demo, or says to skip verification/build/install (e.g. "just give me the source code fast," "quick POC," "skip the build check," "demo purposes," "don't bother verifying it"). For anything else — including a plain "scaffold/generate/bootstrap a UAB app" request with no speed/POC framing — prefer uab-app-creator instead, which actually confirms the generated code installs cleanly and passes a security audit before handing it back.
---

# UAB App Creator — Fast (zero-verification)

This is the fast, explicitly-unverified counterpart to `uab-app-creator`.
It covers the exact same interview and code-generation ground — the same
decision matrix, the same Next.js+MUI / Python+FastAPI scaffolds, the same
UAB branding and Ory Hydra OIDC login — but it **never runs a package
manager or a build tool**. No `npm install`, `npm audit`, `npm run build`,
`pip install`, dev server, health check, or even the free/offline static
checklist `uab-app-creator` runs. It writes source files and zips them,
nothing else.

**Why this exists:** `uab-app-creator`'s `npm install`/`npm audit` steps
are network-bound and can still hang or hit TrueForge's Daytona-sandbox
per-command timeout, even with build/serve steps already stripped out.
For a quick proof-of-concept or demo, that risk isn't worth the wait —
this skill trades away all in-sandbox assurance for speed and reliability.
Because nothing here ever touches npm/pip, this skill needs **no runtime
present in the sandbox at all** — no Node, no Python, no preflight check.

**The output is UNVERIFIED.** The generated code has not been confirmed to
actually install or compile. Say this plainly every time (see the
Report-back step) — never imply the app "works" or was "tested."

**The persona throughout is a non-technical "project leader."** Never use
words like "framework", "API", "repository", "stack", "backend",
"frontend", or "container" with them. You make every technical decision
using `references/decision-matrix.md`. This machine doesn't have to belong
to the project leader personally — running this skill is just as likely to
be a technical teammate's or IT contact's, on their behalf.

## Mode detection

- No prior answers captured yet (a fresh invocation, no idea description
  already supplied) → **interactive mode**.
- The user already supplied a filled-in idea/answers (e.g. pasted a
  completed IDEA.md-style questionnaire, or gave a detailed one-shot
  description covering who/what/data/sensitivity/login) → skip straight to
  **generation mode**, treating what they gave you as the interview
  answers. Confirm your understanding back to them in one summary before
  writing PLAN.md, the same as you would after a live interview.

## Interactive mode

1. Ask the questions in `references/interview-questions.md` **one at a
   time**, in plain language. Never reveal a question number.
2. After each answer, briefly confirm what you heard before asking the
   next one.
3. Once all questions are answered, follow the "After all questions are
   answered" steps at the bottom of `references/interview-questions.md`:
   ask about mockups/examples if not already covered, summarize the whole
   idea back to them, then write `PLAN.md` to the repo root using the
   template in that same file.
4. Tell them: "I've written a plain-English plan — take a look and just say
   'looks good' when you're ready and I'll build the whole thing. Just a
   heads-up: this fast path generates the code but doesn't install, build,
   or check it — that's the trade-off for getting it quickly."

### HARD STOP

**Stop here. Do not generate anything else in this turn** — not the app
scaffold, not any other file — even if you're confident they'll approve it.
Only a **new, separate reply** from the project leader approving the plan
(e.g. "looks good") moves you into generation mode. This boundary is about
approval, not build speed — it applies here exactly as it does in
`uab-app-creator`.

If you're running under a tool that has its own plan-mode/approval feature
(for example Claude Code's plan mode), use it ONLY to cover "interview the
project leader and write PLAN.md" — never bundle "write PLAN.md" together
with "then generate the rest of the app" into that same upfront plan. The
project leader cannot be approving PLAN.md's actual content at that point,
because PLAN.md doesn't exist yet. Once PLAN.md is written, exit or complete
the tool's planning step without pre-approving anything further, show the
project leader what you wrote, and wait for their own separate reply.
Folding both approvals into one results in the whole app being built before
the project leader has seen PLAN.md at all. This is the single most
important rule in this entire skill.

## Generation mode

Work through these steps in order. Don't ask permission before each file —
generate everything, then package.

**a. Apply the decision matrix.** Read all answers (factor in Q12 — see
`references/interview-questions.md`) and silently apply
`references/decision-matrix.md` to decide: app type (web vs. worker), auth
(none / Hydra / stubbed), data storage, external integrations, and AI
usage.

**b. Generate the outputs**, each pulling in its reference file(s) only
when you reach that step:
   1. App scaffold — `references/scaffold-web-nextjs.md` (Q4 = web) or
      `references/scaffold-worker-python.md` (Q4 = background worker),
      pulling in `references/branding-theme.md` always, and
      `references/auth-hydra-oidc.md` / `references/data-layer.md` when the
      matrix calls for them.
   2. `.env.template` — `references/env-template.md`.
   3. `README.md` — `references/readme-template.md`.

There is no preflight/runtime check and no generation-manifest step here
(unlike `uab-app-creator`) — this flow never runs npm/pip, so Node/Python
being present or absent on this machine is irrelevant, and there's no
verification loop downstream that a manifest would feed into. Just
generate the files.

**c. Package.** Run `scripts/package-app-fast.sh` from the generated app's
folder. Unlike `uab-app-creator`'s `package-app.sh`, this has no gate to
pass — it zips whatever was generated, with the same defensive excludes
(no `node_modules/`, `.git/`, `.env`, `.env.local`, etc. — most won't exist
here since nothing was ever installed, but the excludes are kept in case
this code is later run through the full flow or by hand). If it reports
failure because no archiving tool was found on this machine, tell the
project leader plainly that the app folder itself is ready to hand off,
and that whoever picks it up can zip it themselves.

**Never zip the app folder any other way** — not with a raw `zip`/`tar`/
`Compress-Archive` command you write yourself. `scripts/package-app-fast.sh`
is what enforces the same exclude list every time; a hand-rolled zip
command risks shipping a real secret or a stray local data file.

**d. Report back**, in plain language:
   - What the app does (one sentence).
   - That you generated the source code, but this fast path does **not**
     install dependencies, build, run, or check the app in any way — say
     this plainly, every time, not as a caveat buried at the end.
   - Where to find the downloadable zip file, and that it contains the
     complete source code — nothing needs to be installed or configured to
     open and read it.
   - That before relying on this beyond a quick demo, someone needs to
     actually install dependencies and build it — one or two commands
     listed in the included README — and that if real assurance it
     installs/builds/passes a security audit matters, `uab-app-creator`
     (the non-fast version) does that verification before handing back the
     zip. Deploying it somewhere permanent is a separate step for a
     developer or their IT team either way.

## Principles to preserve

- Plain language only with the project leader — every technical decision
  in `references/decision-matrix.md` is made silently, never surfaced as a
  question unless the matrix itself says to ask a follow-up (Q7, Q9).
- Never ask about languages, frameworks, databases, or cloud services.
- Never leave a connection-string placeholder or `YOUR_..._HERE` value for
  the project leader to fill in for anything the app can provide locally —
  see the DATA STORAGE section of `references/decision-matrix.md` and
  `references/data-layer.md` for how the app works with zero configuration
  out of the box.
- This skill never runs a git command and never writes Azure Bicep,
  `azure.yaml`, or pipeline files. If the project leader asks about
  deploying to Azure or setting up automatic deployment, tell them plainly
  that's a separate step for their IT team or a developer — not something
  this skill sets up.
- Never run a package manager or a build tool (`npm`, `pip`, `npm run
  build`, a dev server, anything) in this flow, for any reason — not "just
  to double-check," not because a step feels quick. That's the entire
  reason this skill exists separately from `uab-app-creator`. If in-sandbox
  assurance is what's actually wanted, that's a sign to use
  `uab-app-creator` instead, not to bend this one.
