# Revision mode — changing an app that already exists

Use this when the project leader asks for changes to an app this skill
generated before — earlier in this session or in an earlier one ("change
the greeting", "add a page for…", "can people also…"). **Revise, never
regenerate.** The existing code holds work that a new generation would
throw away: fixes `uab-app-qa` made, `uab-branding`'s theme and footer,
and any edits a reviewer made on GitHub.

## 0. Before you start: the current code must be in this sandbox

This skill never restores code itself and never runs a git command. The
orchestrating process restores the app first — normally with
`uab-deploy --sync`, which brings the latest version from GitHub (the
open review branch, or the main branch once a change has been merged) —
and then invokes this mode against that folder.

- The app folder (with `PLAN.md`) is present → continue.
- It isn't present → **stop** and say plainly that the app's current
  code isn't in this workspace yet and needs restoring from its GitHub
  repository (or from the downloadable zip, if it was never pushed)
  before anything can be changed. Never rebuild it from memory or from
  the conversation.

## 1. Understand the app as it is now

Read `PLAN.md` (including any `## Change history`), `README.md`, and the
parts of the code the request touches. The code — not your memory of an
earlier conversation — is the truth: it may contain QA fixes or a
reviewer's edits you didn't make.

## 2. Restate the change, then decide whether it needs approval

Summarize the request back in plain language — what people using the
app will see or be able to do differently. Persona rules still apply: no
"framework", "API", "repository", "component", file names, etc.

**Feature-level change → HARD STOP for approval**, exactly like the
generation HARD STOP in `SKILL.md`:
- a new or removed page or feature,
- different data being stored or shown, or data stored for longer,
- who can use the app or whether login is needed,
- a new connection to another system, or any use of AI,
- anything that changes the answer to the data-sensitivity question
  (re-check DATA SENSITIVITY in `references/decision-matrix.md`; add or
  update the sign-off banner in `PLAN.md` if it now applies).

Update `PLAN.md`'s descriptive sections to describe the app *after* the
change, add the pending entry to `## Change history` (step 5), show the
project leader, and **stop**. Only a new, separate "looks good" reply
moves on to step 3.

**Small change → proceed in the same turn** after stating what you'll
change: wording, labels, colors or spacing within the UAB brand, layout
tweaks, or fixing something the project leader says doesn't work. **If
you're unsure which kind it is, treat it as feature-level.**

## 3. Make targeted edits

- Change only the files the request needs. Keep the existing structure,
  names, and conventions — the same reference files that generated the
  app govern changes to it (`scaffold-web-nextjs.md` /
  `scaffold-worker-python.md`, `data-layer.md` for new stored fields,
  `auth-hydra-oidc.md` for login changes, `decision-matrix.md` for any
  new technical decision — still made silently).
- **Branding:** never re-run `uab-branding` GENERATE and never rewrite its
  files (`src/theme/*`, `Footer.tsx`, the logo, the skip link and
  landmarks). Any new page, form, dialog, or status message follows
  `uab-branding`'s rules literally — `references/forms.md`,
  `references/aria-patterns.md`, `references/landmarks-and-structure.md`,
  `references/color-and-status.md`: copy their snippets, don't paraphrase.
  One real `<h1>` per page.
- Don't undo earlier QA fixes. If a fix is in the way of the change, keep
  its intent.
- New libraries only if the change genuinely needs one — add it to the
  dependency file and mention it in the report (this skill still never
  runs `npm`/`pip`; `uab-app-qa` installs and checks it).
- Keep `README.md` and `.env.template` accurate if run steps or settings
  changed.
- Never delete the app's local data folder or anything in the exclude
  list.

## 4. Re-package

Run `scripts/package-app-fast.sh` from the app folder, exactly as in
generation mode, so the downloadable zip matches the revised code.

## 5. Record the change in PLAN.md

Append to a `## Change history` section at the end of `PLAN.md` (create it
the first time) — newest entry last, plain English, no file paths:

```markdown
## Change history

### 2026-10-08 — Personalized welcome message
- **Asked for:** "Say 'Welcome, <name>' instead of 'Hello <name>'."
- **What changed:** The greeting on the home page now says "Welcome, …".
- **Status:** Changed — not yet tested.
```

For a feature-level change, write the entry at the approval stop with
**Status:** "Waiting for approval", and update it to "Changed — not yet
tested" once you've made the edits. `uab-app-qa` and `uab-deploy` don't
edit `PLAN.md`; the orchestrating process sets the status to **"Tested —
sent for review"** after QA passes and **before** the push, so the entry
travels in the same commit as the change.

Never record the pull request link in `PLAN.md`, and never push again
just to update `PLAN.md` — each push is a commit on the pull request. The
link belongs in the reply to the project leader.

There's no `## Change history` section after the first build — it starts
with the first revision.

## 6. Report back

In plain language:
- what changed, from the project leader's point of view;
- that the change is **not yet tested** — say it plainly, every time,
  the same as after generation;
- what happens next: it gets tested, then sent to GitHub for review
  (the orchestrating process runs those steps).

## Hard rules

- Never regenerate the whole app to make a change. Only start over if the
  project leader explicitly asks to start over — and then it's a new
  generation with a new `PLAN.md`, not a revision.
- Never skip the HARD STOP for a feature-level change, and never fold
  the approval and the edits into one turn.
- Never rewrite `uab-branding`'s generated files; follow its rules for
  anything new.
- Never restore, rebuild, or guess missing code — stop and ask for it to
  be restored (step 0).
