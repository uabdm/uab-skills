# Verify & Self-Heal — deep review checklist

The project leader cannot fix code. After generating everything, you MUST
prove the app is sound before telling them it is done. `scripts/
verify-web-app.sh` / `verify-worker-app.sh` handle the mechanical
install/audit loop (`npm install` + `npm audit`, or `pip install`), AND (as
of the MECHANIZED items below) run `scripts/lint-checklist.sh` — a script
that asserts everything on this list that's actually assertable by
grep/test, the same way every run. These scripts deliberately do NOT run
`npm run build`, start a dev server/uvicorn, or smoke-test any route — that
happens later, at actual deployment time, not inside this code-generation
step (see `SKILL.md`'s Verify step for why: it was the source of sandbox
timeouts). That split (install/audit + lint-checklist here, build/run
elsewhere) exists because a model reliably running a script and reacting
to a printed `FAIL:` line is a much lower bar than the same model reliably
self-auditing this entire list from memory across many separate tool
calls — the second one is where a weaker or less agentic model quietly
skips steps instead of failing loudly. Do not manually re-derive an item
tagged **MECHANIZED** below by reading code; trust `lint-checklist.sh`'s
output for it and spend your own judgment on the items tagged **STILL
MANUAL** instead. Loop: fix, re-run the affected script, repeat, until
`verify-*.sh` (which includes `lint-checklist.sh`) passes with zero errors
AND every STILL MANUAL item below is confirmed.

- **STILL MANUAL.** The generated file set matches the generation manifest
  emitted at the start of generation (see `SKILL.md`) — every file listed
  was actually written and every conditional rule fired as recorded. This
  is what catches a silently-skipped module that still builds cleanly and
  goes unnoticed. Nothing can script this without the manifest itself being
  a structured, diffable file, which it currently isn't.
- **MECHANIZED** (`lint-checklist.sh`). (Web app) `package-lock.json`
  exists — `npm ci` in the Dockerfile fails without it, and
  `scripts/package-app.sh` ships it in the zip.
- **STILL MANUAL.** Every import resolves to a file/package that actually
  exists. Every file referenced in layout/routing/theme exists with the
  exact name. `verify-web-app.sh` no longer runs `npm run build` (see the
  top of this file), so nothing here is caught by a compile failure — this
  item now has to be checked by actually reading the code, not skimmed as
  "the build will catch it."
- **STILL MANUAL.** Every environment variable the code reads appears in
  `.env.template`, and no connection-string placeholder was left for the
  user to fill in for anything the app can provide locally. If a login was
  generated, `.env.local` has real working values (not placeholders) for
  `NEXT_PUBLIC_AUTH_URL`, `NEXT_PUBLIC_CLIENT_ID`, and
  `NEXT_PUBLIC_REDIRECT_URL`.
- **MECHANIZED** (`lint-checklist.sh`), partially. `.gitignore` exists and
  covers `.env` and `.env*.local` (not just `.env.local`) alongside
  `node_modules/`/`__pycache__` and the `.data`/`.localstorage` fallback
  dirs (see `data-layer.md`). No external-integration env var anywhere in
  the generated code, `.env.local`, or `.env.template` is prefixed
  `NEXT_PUBLIC_`. `.env.template` is also checked for known secret-key/token
  *prefixes* (a high-precision, low-recall signal). **STILL MANUAL**: the
  exhaustive "no real value anywhere, only placeholders" judgment call,
  since a generic heuristic can't reliably tell a real value apart from
  this skill's own long `YOUR_..._HERE`-style placeholders.
- **STILL MANUAL.** There are no leftover TODO stubs that would stop the
  app from starting (domain-logic TODOs are fine; broken wiring is not).
- **MECHANIZED** (`lint-checklist.sh`). If a login was generated,
  `oidcConfig.ts` has an `onSigninCallback`, uses snake_case `oidc-client-ts`
  field names (`client_id`, `redirect_uri`, `response_type` — never
  `oidc-react`'s old `clientId`/`redirectUri`/`responseType`), and does NOT
  set `post_logout_redirect_uri`. Every auth consumer imports
  `useOptionalAuth()` from `src/auth/useOptionalAuth.ts` — none import
  `useAuth()` from `react-oidc-context` directly (except
  `AuthProviderWrapper.tsx`'s own `AuthErrorUrlCleanup`, which legitimately
  touches the raw library). `removeUser(` does not appear anywhere in
  `src/` — every sign-out button must call `signoutRedirect(` instead,
  since a bare `removeUser()` call as the sign-out action is a regression
  (it doesn't end the Hydra session). **STILL MANUAL**: that
  `onSigninCallback` actually strips URL query params via
  `history.replaceState` (`lint-checklist.sh` only confirms the hook
  exists, not its body) and that `AuthProviderWrapper.tsx` mounts
  `<AuthProvider>` unconditionally.
- **Local-run readiness** (each of these prevents `docker build`, or a
  developer's first `npm install`/`pip install`, from breaking on a
  different machine than the one that generated the app) —
  **MECHANIZED** (`lint-checklist.sh`):
  - `.dockerignore` exists at the repo root and covers `.env`, `.data`,
    `.localstorage` (see `data-layer.md`).
  - (Web app) the Dockerfile is on `node:22-alpine` or newer in BOTH
    stages, and `package.json` does NOT list `better-sqlite3` — the local
    SQLite storage uses the built-in `node:sqlite` (Node >= 22).
- **STILL MANUAL.** If DATA SENSITIVITY (Q7) was answered A–E: PLAN.md has
  the compliance banner as its first section, README.md has the matching
  "Before you go live" section, and login is present regardless of what
  Q8/USERS said — if Q8 was answered C ("no login") but Q7 flagged sensitive
  data, confirm login was generated anyway and PLAN.md explains the
  override — unless the EXTERNAL USERS escalation applied (non-UAB
  audience), in which case confirm auth was stubbed and PLAN.md flags the
  IT decision instead.
- **STILL MANUAL.** If Q6 was answered B or C: a stub integration file
  exists for every system named in the description, each with matching env
  var name comments in `.env.template` and real blank stub lines in
  `.env.local`, and PLAN.md/README.md both list every named system —
  confirm the count of stub files matches the count of systems described,
  not just that at least one exists.
- **MECHANIZED** (`lint-checklist.sh`). `public/uab-logo-white.png` exists
  (copied from the bundled `assets/uabCoreLogoWhiteSmall.png` — see
  `branding-theme.md`) and `AppShell.tsx` references it, is a plain HTML
  `<img>` (not `next/image`), and is styled with `maxWidth: 270` and
  `height: 'auto'`. The AppBar references `theme.palette.primary.main`
  (fixed UAB Green). **STILL MANUAL**: actually toggling the theme and
  confirming the AppBar's background and logo stay visually identical in
  both modes while the page content behind it changes, and that the logo's
  *rendered* proportions (not just its style props) aren't squished.
- **MECHANIZED** (`lint-checklist.sh`). `Footer.tsx` contains the required
  text — Contact UAB, Privacy, Terms of Use, the copyright line, and
  Nondiscrimination Statement — and does NOT contain "A-Z Site Index".
  **STILL MANUAL**: it actually renders on every page (check both a page
  inside AppShell and, if generated, a page inside AuthGate), the dialog
  opens with the exact statement text, and the responsive mobile/desktop
  layouts match spec.
- **MECHANIZED** (`lint-checklist.sh`), if a Drawer nav was generated (4+
  nav items): both the `variant="permanent"` and `variant="temporary"`
  branches exist, and the main content `Box` has `minWidth: 0`. **STILL
  MANUAL**: the Drawer and content are genuinely flex siblings rather than
  the Drawer floating over an unoffset content area, and the breakpoint
  switch actually happens at `md` when the viewport is resized — a passing
  grep for `minWidth: 0` doesn't guarantee the flex layout around it is
  correct.
- **OPTIONAL / STILL MANUAL.** `verify-web-app.sh` no longer starts the app
  (see the top of this file), so there is nothing running to visually
  render by default — do not start one yourself (`npm run dev`, `npm run
  build`) just to perform this check; that reintroduces the exact sandbox
  timeout risk this skill removed the build/serve step to avoid. This
  check is skipped in the standard flow. If the project leader specifically
  asks to see what the app looks like before downloading it, and your tool
  can genuinely render a page (a browser tool, an MCP browser server, a
  preview pane), that's the one case where starting the app locally to look
  at it is worth the risk — do so via `scripts/bg-run.sh`/`scripts/
  bg-status.sh`, never a blocking command, and confirm the home page at a
  standard desktop width (~1280px) and mobile width (~375px): nothing
  overlaps, no unintended horizontal scrollbar, the footer renders as
  specified without wrapping, and the logo's rendered proportions match its
  source file. Otherwise, do NOT tell the project leader layout was
  visually confirmed — say plainly that only the automated code checks ran.
- **MECHANIZED** (`scripts/package-app.sh` itself, after zipping). Confirms
  `<app-name>.zip` exists, is non-empty, and spot-checks that it does NOT
  contain `node_modules/`, `.next/`, `__pycache__/`, `.venv/`, `.git/`,
  `.verify/`, `.env`, `.env.local`, `.data/`, or `.localstorage/`.

## Hard rules

- Do NOT tell the project leader the app is ready until `verify-web-app.sh`
  / `verify-worker-app.sh` passes (which includes `lint-checklist.sh`),
  every STILL MANUAL item above is confirmed, AND `scripts/package-app.sh`
  has produced the zip. `package-app.sh` mechanically refuses to run at all
  unless `.verify/PASSED` exists and matches the current source — this is
  the enforced version of this rule, not just a reminder to follow it.
- Loop: when you fix something, re-run the affected script.
- Report the result in plain, non-technical language, e.g.: "I checked
  every part of your app for errors, ran a security scan on everything it
  depends on, and packaged everything into a zip file you can download."
