---
name: uab-idea-builder
description: Turns a UAB project idea into a complete, deployable application — interviews a non-technical project owner one question at a time, silently applies UAB's platform decision matrix (auth, data storage, sensitivity review, hosting), then generates a full Next.js+MUI or Python/FastAPI app with Azure Bicep infrastructure, three-branch Azure DevOps pipelines, Ory Hydra OIDC login, and UAB branding — and verifies it actually builds and runs before handing it off. Use this whenever the user wants to turn an app idea into working code for the UAB platform, mentions "IDEA.md" or the platform scaffold repo, asks to scaffold/generate/bootstrap/build a new UAB app or Container App, or is interviewing a non-technical stakeholder about what an app should do (even if they don't use the word "scaffold"). Also trigger for requests like "build me an app that does X for my department" or "set up a new UAB project that needs Azure SQL and staff login."
---

# UAB Idea Builder

This skill is the Claude Code / skills-capable counterpart to `IDEA.md` in
this repo. `IDEA.md` itself stays a separate, zero-install path (paste it
into any chat AI, nothing runs locally) — this skill is for when a coding
tool is available and can run commands, and it trades that raw-document
approach for progressive disclosure (only load the reference file for the
output currently being generated) and real scripts for the mechanical steps
(git branch setup, the install/build/serve verification loop, pushing to
`develop`).

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
(none / Hydra / stubbed), data storage, external integrations, AI usage, and
the always-on items (Key Vault, Container Apps, monitoring, scaling).

**b. Get onto `develop`.** Run `scripts/setup-develop-branch.sh` from the
project root before writing any scaffold file (never before PLAN.md, which
needed none of this). Read its output:
   - `GIT_MISSING` → stop, don't generate scaffold files, and give the
     project leader the fallback message in `references/git-workflow.md`.
   - Anything else → it succeeded; proceed.

**c. Emit a generation manifest.** Before writing any scaffold file, list
every file about to be generated plus every conditional rule that fired
(auth on/off, login gate on/off, data modules, integrations, sensitivity
banner, scaling numbers). `references/verification-checklist.md`'s first
check compares the actual generated files against this manifest — a
silently-skipped module (e.g. a missing `monitor.bicep`) can otherwise still
build cleanly and go unnoticed.

**d. Generate the outputs**, each pulling in its reference file(s) only
when you reach that step:
   1. App scaffold — `references/scaffold-web-nextjs.md` (Q4 = web) or
      `references/scaffold-worker-python.md` (Q4 = background worker),
      pulling in `references/branding-theme.md` always, and
      `references/auth-hydra-oidc.md` / `references/data-layer.md` when the
      matrix calls for them.
   2. `.env.template` — `references/env-template.md`.
   3. The three pipelines — `references/pipelines-azure-devops.md`.
   4. `azure.yaml` — `references/azure-yaml.md`.
   5. `infra/` — `references/infra-bicep.md`.
   6. `README.md` — `references/readme-template.md`.

**e. Verify.** Run `scripts/verify-web-app.sh` or `scripts/verify-worker-app.sh`
depending on app type, then work through the judgment checklist in
`references/verification-checklist.md`. Loop: fix, re-run the affected
script, repeat until everything passes with zero errors. **Never tell the
project leader the app is ready before this passes.**

**f. Push.** Only after verification passes, run
`scripts/push-to-develop.sh`. If it reports `NO_REMOTE_CONFIGURED`, that's
not a failure — tell the project leader their IT team needs to connect the
repo and push `develop` themselves (see `references/git-workflow.md`).

**g. Report back**, in plain language:
   - What the app does (one sentence).
   - That you built it and confirmed it runs and the page loads correctly.
   - That nothing needs to be filled in by hand — data, secrets, and
     connections are all set up automatically when it deploys.
   - That their Development version is deploying automatically now (or, if
     the push couldn't run, that their IT team needs to do that one step
     first).
   - That it will go through a review step before reaching everyone else,
     and they'll get a link once it's live.

## Principles to preserve

- Plain language only with the project leader — every technical decision
  in `references/decision-matrix.md` is made silently, never surfaced as a
  question unless the matrix itself says to ask a follow-up (Q7, Q9).
- Never ask about languages, frameworks, databases, or cloud services.
- Never leave a connection-string placeholder or `YOUR_..._HERE` value for
  the project leader to fill in — see the DATA STORAGE and EXISTING SYSTEM
  INTEGRATION sections of `references/decision-matrix.md` for why, and
  `references/data-layer.md` for how the zero-config fallback works.
- `scripts/push-to-develop.sh` only ever touches `develop`, the one branch
  with no approval gate — never point any part of this skill at `qa` or
  `production`. Creating and approving into those stays a manual step for
  IT (see `references/readme-template.md`).
