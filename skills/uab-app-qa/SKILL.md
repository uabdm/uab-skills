---
name: uab-app-qa
description: Post-build runtime QA for an already-generated app — installs dependencies, runs and auto-fixes npm audit findings, runs a real production build and fixes every compile/type/lint error, then starts the app and drives it with a real headless browser (Playwright) to smoke-test every route and interactive flow: forms (happy path + validation), dialogs/modals, theme toggle, responsive nav — capturing actual browser console errors and React hydration warnings, not just HTTP status codes. Loops fixing and re-testing until the app is fully clean. This is the deliberately-deferred step `uab-app-creator`'s own verify script explicitly skips (install/audit only, never build or run, to avoid sandbox timeouts) — use this skill AFTER that generation step, once the app is in a real environment where a build and dev server can safely run: when the user says the app is built but broken, asks to "debug/fix/test/audit this app," "make sure it actually works," "click through it and test the forms," reports a runtime/console/hydration error, or wants confirmation beyond "the code compiles." Not for interviewing about what to build (see `uab-app-creator`/`uab-app-builder`) and not for brand/WCAG-specific checks (see `uab-branding`'s AUDIT mode, which this skill calls into rather than duplicating).
---

# UAB App QA — install, audit, build, and functional testing

This fills a gap the app-creator family leaves open on purpose.
`uab-app-creator`'s `verify-web-app.sh` runs `npm install` and `npm audit`
but explicitly never runs `npm run build`, starts a dev server, or visits a
single route — its own `references/verification-checklist.md` says why: a
cold build or a long-lived dev-server+curl loop was the confirmed cause of
sandbox timeouts on TrueForge's Daytona-backed generation sandbox, and
building/running happens "later, at actual deployment time." That's the
right call for a code-generation step running inside a throwaway sandbox —
but it means nothing has ever actually run the app or clicked anything in
it. Concretely: a UAB app built by `uab-app-creator` + `uab-branding`
shipped with a footer dialog that crashed the instant a user clicked it
(`<h2>` nested inside `<h2>`, a Next.js hydration error) — `npm run build`
wouldn't have caught it either; only actually opening the dialog in a real
browser would have.

**This skill is that later step.** Run it once the app is somewhere a
build and a dev server can safely run for real — a person's own machine, a
CI runner, an unzipped download, this session's own working directory —
not folded back into `uab-app-creator`'s generation flow.

## Critical: this Next.js is not the Next.js you know

If the target app's own `AGENTS.md`/`CLAUDE.md` carries the standard
generated warning ("This is NOT the Next.js you know... Read the relevant
guide in `node_modules/next/dist/docs/` before writing any code"), take it
literally, every time you touch this skill's Phase 2 or Phase 3: **read the
matching page in that app's own `node_modules/next/dist/docs/` before
diagnosing a build or runtime error that looks Next.js-API-shaped** —
routing, server actions, `headers()`/`cookies()`/`params`, metadata,
middleware. Training-data knowledge of "how Next.js works" is exactly the
wrong instinct to diagnose a fork with breaking changes; a plausible-looking
fix based on the wrong API surface can cost more time than reading the doc
first would have.

## Scope detection

- Target app: an explicit path or zip the user names, or the current
  working directory if it already looks like an app root (`package.json`
  at the top, or `requirements.txt`/`pyproject.toml` for a worker). If
  given a zip, extract it first.
- App type: **web** (`package.json` with `next` as a dependency) or
  **worker** (Python, no UI). This skill's depth is in the web path
  (Phases 1–4 below in full). For a worker app, Phase 1 becomes `pip
  install` + `pip-audit`/`safety` if available, Phase 2 is whatever test
  command the project defines (`pytest`, etc.), and Phase 3 (browser
  smoke test) doesn't apply — there's no UI to click. Report that plainly
  rather than silently skipping it without saying so.

## Workflow (web app)

Work through these phases **in order**, every time — do not skip Phase 3
just because Phase 1 and 2 passed. A clean build proves the code compiles;
it proves nothing about what happens when a real browser renders and
hydrates the page, which is exactly the class of bug (hydration errors,
console errors, broken interactions) this skill exists to catch.

### Phase 1 — Dependencies & security

`references/dependency-audit.md`. Run `scripts/install-and-audit.sh`
(or the equivalent commands by hand if the script doesn't fit the
environment). Don't assume a prior skill already did this — this skill
must be self-sufficient whether the app came from `uab-app-creator`
(already installed/audited), `uab-app-creator-nobrand`/`-fast` (never
installed at all), or a zip handed to you cold. Loop: fix, re-run, repeat
until `npm install` succeeds clean and `npm audit --audit-level=high`
reports zero unresolved high/critical vulnerabilities.

### Phase 2 — Build

`references/build-and-fix.md`. Run `npm run build` (and `npm run lint` if
the project defines it). Read the actual error and fix the real defect in
source — never silence it with a blanket `// @ts-ignore`, an
`eslint-disable` on the offending line, or a `try/catch` that swallows the
real problem. Loop: fix, rebuild, repeat until it passes with zero errors.

### Phase 3 — Runtime & functional smoke test

`references/functional-smoke-test.md`. Start the app, then drive it with a
real headless browser (Playwright) across every discovered route and
interactive element: every form (both the happy path and the empty/invalid
validation path), every dialog/modal, the theme toggle, and the responsive
nav at both mobile and desktop widths — capturing actual `console.error`/
`pageerror` events, not just HTTP status codes. Any failure here sends you
back to Phase 2 (fix, rebuild) and then re-run Phase 3 from the top — a
partial re-test after a fix is not enough, because a fix in one component
can regress another route you already passed.

### Phase 4 — Branding/WCAG cross-check

If the app was built with `uab-branding` (check for `src/theme/LightTheme.js`
importing from `themeShared.js`, or just ask if unsure), invoke
`Skill(uab-branding)` in its AUDIT mode against this app's source tree as
part of this pass. Don't re-derive brand-color, typography-scale,
landmark, or focus-ring checks here — that skill already owns that ground
in detail; this skill's job is dependency health, build correctness, and
runtime/functional correctness, which `uab-branding`'s own checklist
doesn't cover.

### Phase 5 — Report

Plain-language summary: what ran and passed, what was found and fixed
(one line per fix, with a `file:line` citation), the current `npm audit`
status, and any item that couldn't be verified in this environment and
needs a human look (e.g., a flow that requires real third-party
credentials, a payment integration, an external service this sandbox can't
reach). Never say "fully working" if any phase didn't actually complete —
say exactly which phase got furthest and why the rest couldn't run.

## Backgrounding long commands

The same sandbox-timeout risk `uab-app-creator` documents for `npm install`
and `npm run build` applies here too. `scripts/bg-run.sh <label>
<command...>` runs a command fully detached and returns immediately;
`scripts/bg-status.sh <label>` polls it cheaply (repeat every ~10–15s
until it prints `DONE`). Use this for Phase 1's install and Phase 2's
build. For Phase 3's dev server — a *persistent* process, not a one-shot
job that finishes — if the current harness has its own native
backgrounding (for example Claude Code's Bash `run_in_background` plus a
`Monitor` watching the log until it prints "Ready in"), prefer that
instead; it's the same idea and doesn't need the `.qa/bg/` bookkeeping
`bg-run.sh` uses for jobs that terminate. The scripts are the portable
fallback for environments without that.

## Browser automation: Playwright first, `claude-in-chrome` optional

Playwright is the primary mechanism — see
`references/functional-smoke-test.md` for the full pattern. It's headless,
scriptable, captures real console/page errors deterministically, and needs
nothing beyond `npx playwright install chromium`. If the current session
also has a working `claude-in-chrome` connection, it's a fine
*supplementary* way to eyeball something visually (e.g. confirm a layout
fix actually looks right, the way a screenshot would) — but don't make it
the primary or only verification method: it depends on a browser extension
the user may not have installed or may decline (this is expected — treat a
decline as "not available," never press the point), and it doesn't give
you the same reliable, scriptable console-error capture Playwright does.

## Hard rules

- Never tell the user the app is "fully clean" or "working" until every
  phase above has actually run and passed with zero errors — no build
  error, no lint error, no unresolved high/critical `npm audit` finding,
  no console error or hydration warning on any route, no broken form or
  dialog.
- Never suppress an error to make a check pass. No blanket `ts-ignore`,
  no `eslint-disable` on the failing line, no `try/catch` that hides a
  real defect, no `npm audit fix --force` without first checking the
  advisory/changelog for breaking changes. Fix the actual cause.
- Never skip Phase 3 because the build passed. A clean `npm run build` and
  a working app are different claims — the confirmed nondiscrimination-
  dialog bug that motivated this skill built cleanly and only broke when a
  real browser rendered and hydrated it.
- Loop: whenever you fix something, re-run the affected phase — and every
  phase after it — before calling the pass done. A fix isn't verified
  until the thing it fixed, and everything downstream of it, has actually
  been re-checked.
- If something can't be verified in this environment (no real credentials,
  no reachable external service), say so plainly in the report instead of
  marking it passed or silently leaving it out.

## Reference index

- `references/dependency-audit.md` — `npm install`/`npm audit` loop,
  common incompatibility patterns and how to actually fix them (not just
  detect them).
- `references/build-and-fix.md` — the build/lint loop, common Next.js
  App Router and TypeScript error categories.
- `references/functional-smoke-test.md` — the Playwright methodology:
  route discovery, console/error capture, and the interaction patterns
  (forms, dialogs, theme toggle, responsive nav).
- `references/common-bug-patterns.md` — a running catalog of confirmed
  runtime bugs and their fixes, seeded from real findings in generated
  apps — check here before re-deriving a fix from scratch.
