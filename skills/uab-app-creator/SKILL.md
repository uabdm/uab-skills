---
name: uab-app-creator
description: Turns a UAB project idea into a working local application — interviews a non-technical project owner one question at a time, silently applies UAB's platform decision matrix (auth, data storage, sensitivity review), then generates a full Next.js+MUI or Python/FastAPI app with Ory Hydra OIDC login and UAB branding, verifies it actually builds and runs, and packages the whole project into a downloadable zip. This is the lightweight, code-only counterpart to the full UAB app builder — it never touches git, never generates Azure Bicep infrastructure, and never sets up deployment pipelines; it just hands back working source code. Use this whenever the user wants a UAB app scaffold to run locally or hand off to a dev team without setting up Azure deployment yet, mentions "IDEA.md," asks to scaffold/generate/bootstrap a UAB app as source code / a zip / a download, or is interviewing a non-technical stakeholder about what an app should do (even if they don't use the word "scaffold").
---

# UAB App Creator

This is the lightweight counterpart to the full UAB app builder skill. It
covers the exact same interview and code-generation ground — the same
decision matrix, the same Next.js+MUI / Python+FastAPI scaffolds, the same
UAB branding and Ory Hydra OIDC login — but stops at working source code. It
never runs a git command, never generates Azure Bicep infrastructure, and
never writes a deployment pipeline. The deliverable is a verified,
runnable app packaged into a single zip file, not a deployed environment.

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
   'looks good' when you're ready and I'll build the whole thing."

### HARD STOP

**Stop here. Do not generate anything else in this turn** — not the app
scaffold, not any other file — even if you're confident they'll approve it.
Only a **new, separate reply** from the project leader approving the plan
(e.g. "looks good") moves you into generation mode.

If you're running under a tool that has its own plan-mode/approval feature
(for example Claude Code's plan mode), use it ONLY to cover "interview the
project leader and write PLAN.md" — never bundle "write PLAN.md" together
with "then generate the rest of the app" into that same upfront plan. The
project leader cannot be approving PLAN.md's actual content at that point,
because PLAN.md doesn't exist yet. Once PLAN.md is written, exit or complete
the tool's planning step without pre-approving anything further, show the
project leader what you wrote, and wait for their own separate reply.
Folding both approvals into one — "I'll write PLAN.md, then on approval
generate everything else" — results in the whole app being built before the
project leader has seen PLAN.md at all. This is the single most important
rule in this entire skill.

## Generation mode

Work through these steps in order. Don't ask permission before each file —
generate everything, then verify.

**a. Apply the decision matrix.** Read all answers (factor in Q12 — see
`references/interview-questions.md`) and silently apply
`references/decision-matrix.md` to decide: app type (web vs. worker), auth
(none / Hydra / stubbed), data storage, external integrations, and AI
usage.

**b. Emit a generation manifest.** Before writing any scaffold file, list
every file about to be generated plus every conditional rule that fired
(auth on/off, login gate on/off, data modules, integrations, sensitivity
banner). `references/verification-checklist.md`'s first check compares the
actual generated files against this manifest — a silently-skipped module can
otherwise still build cleanly and go unnoticed.

**c. Generate the outputs**, each pulling in its reference file(s) only
when you reach that step:
   1. App scaffold — `references/scaffold-web-nextjs.md` (Q4 = web) or
      `references/scaffold-worker-python.md` (Q4 = background worker),
      pulling in `references/branding-theme.md` always, and
      `references/auth-hydra-oidc.md` / `references/data-layer.md` when the
      matrix calls for them.
   2. `.env.template` — `references/env-template.md`.
   3. `README.md` — `references/readme-template.md`.

**d. Verify.** Run `scripts/verify-web-app.sh` or `scripts/verify-worker-app.sh`
depending on app type, then work through the judgment checklist in
`references/verification-checklist.md`. Loop: fix, re-run the affected
script, repeat until everything passes with zero errors. **Never tell the
project leader the app is ready before this passes.**

**e. Package.** Only after verification passes, run
`scripts/package-app.sh` from the generated app's folder. It zips up every
source file — excluding installed dependencies, build output, and any real
local secrets — into `<app-name>.zip` alongside the project. Read its
output; if it reports failure because no archiving tool was found on this
machine, tell the project leader plainly that the app folder itself
(`references/readme-template.md` explains what's in it) is ready to hand
off, and that whoever picks it up can zip it themselves.

**f. Report back**, in plain language:
   - What the app does (one sentence).
   - That you built it and confirmed it runs and the page loads correctly.
   - Where to find the downloadable zip file, and that it contains the
     complete, working source code — nothing needs to be installed or
     configured to open and read it.
   - That running it for real (installing dependencies, starting it) takes
     one or two commands listed in the included README, and that if they
     want it deployed somewhere permanent, that's a separate step for a
     developer or their IT team — this skill hands off working code, not a
     live deployment.

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
