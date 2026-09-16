# Verify & Self-Heal — deep review checklist

The project leader cannot fix code. After generating everything, you MUST
prove the app actually works before telling them it is done. `scripts/
verify-web-app.sh` / `verify-worker-app.sh` handle the mechanical
install/build/serve/curl loop. This file covers the judgment-based deep
review — read back through the generated code and confirm every item below.
Do this in a loop and do not stop until every step passes with zero errors;
when you fix something, re-run the affected script step.

- The generated file set matches the generation manifest emitted at the
  start of generation (see `SKILL.md`) — every file listed was actually
  written and every conditional rule fired as recorded. This is what catches
  a silently-skipped module that still builds cleanly.
- (Web app) `package-lock.json` exists — `npm ci` in the Dockerfile fails
  without it, and `scripts/package-app.sh` ships it in the zip.
- Every import resolves to a file/package that actually exists.
- Every file referenced in layout/routing/theme exists with the exact name.
- Every environment variable the code reads appears in `.env.template`, and
  no connection-string placeholder was left for the user to fill in. If a
  login was generated, `.env.local` has real working values (not
  placeholders) for `NEXT_PUBLIC_AUTH_URL`, `NEXT_PUBLIC_CLIENT_ID`, and
  `NEXT_PUBLIC_REDIRECT_URL`.
- `.env.template` contains no real value anywhere — only variable names and
  comments. `.gitignore` exists and covers `.env` and `.env*.local` (not
  just `.env.local`) alongside `node_modules/`/`__pycache__` and the
  `.data`/`.localstorage` fallback dirs (see `data-layer.md`). No
  external-integration env var anywhere in the generated code, `.env.local`,
  or `.env.template` is prefixed `NEXT_PUBLIC_`.
- There are no leftover TODO stubs that would stop the app from starting
  (domain-logic TODOs are fine; broken wiring is not).
- If a login was generated, `oidcConfig.ts` has an `onSigninCallback` that
  strips URL query params via `history.replaceState`, uses snake_case
  `oidc-client-ts` field names (`client_id`, `redirect_uri`, `response_type`
  — never `oidc-react`'s old `clientId`/`redirectUri`/`responseType`), and
  does NOT set `post_logout_redirect_uri`. `AuthProviderWrapper.tsx` mounts
  `<AuthProvider>` from `react-oidc-context` unconditionally (no
  hydration-delay wrapper needed — that pattern was only required for the
  old `oidc-react` package) and also renders the `AuthErrorUrlCleanup` child
  that strips the URL on a failed `?error=...` callback. Every auth consumer
  imports `useOptionalAuth()` from `src/auth/useOptionalAuth.ts` — none
  import `useAuth()` from `react-oidc-context` directly. Grep the generated
  source for `removeUser(` and confirm every sign-out button actually calls
  `signoutRedirect(` instead — a bare `removeUser()` call as the sign-out
  action is a regression (it doesn't end the Hydra session).
- **Local-run readiness** (each of these prevents `docker build`, or a
  developer's first `npm install`/`pip install`, from breaking on a
  different machine than the one that generated the app):
  - `.dockerignore` exists at the repo root and excludes `node_modules` and
    the build-output dir (`.next`/`__pycache__`) plus `.env*`, `.data`,
    `.localstorage` (see `data-layer.md`).
  - (Web app) the Dockerfile is on `node:22-alpine` or newer in BOTH
    stages, and `package.json` does NOT list `better-sqlite3` — the local
    SQLite storage uses the built-in `node:sqlite` (Node >= 22).
- If DATA SENSITIVITY (Q7) was answered A–E: PLAN.md has the compliance
  banner as its first section, README.md has the matching "Before you go
  live" section, and login is present regardless of what Q8/USERS said — if
  Q8 was answered C ("no login") but Q7 flagged sensitive data, confirm
  login was generated anyway and PLAN.md explains the override — unless the
  EXTERNAL USERS escalation applied (non-UAB audience), in which case
  confirm auth was stubbed and PLAN.md flags the IT decision instead.
- If Q6 was answered B or C: a stub integration file exists for every system
  named in the description, each with matching env var name comments in
  `.env.template` and real blank stub lines in `.env.local`, and
  PLAN.md/README.md both list every named system — confirm the count of
  stub files matches the count of systems described, not just that at least
  one exists.
- `public/uab-logo-white.png` exists (copied from the bundled
  `assets/uabCoreLogoWhiteSmall.png` — see `branding-theme.md`) and
  `AppShell.tsx` references it — and the AppBar's background color is
  `theme.palette.primary.main` (fixed UAB Green), NOT a mode-dependent
  color. Toggle the theme and confirm the AppBar's background and logo stay
  visually identical in both modes while the page content behind it
  changes. Confirm the logo renders at a maximum width of 270px, top-left
  of the bar. The logo is a plain HTML `<img>` (not `next/image`), styled
  with exactly `maxWidth: 270, height: 'auto'` and no other `width` or
  `height` set anywhere on it.
- `Footer.tsx` renders on every page (check both a page inside AppShell and,
  if generated, a page inside AuthGate) with exactly: Contact UAB, Privacy,
  Terms of Use, the copyright line, and a Nondiscrimination Statement button
  that opens the dialog with the exact statement text — and does NOT
  include an A-Z Site Index link.
- If a Drawer nav was generated (4+ nav items): the Drawer and the main
  content are flex siblings (the Drawer is not floating over an unoffset
  content area), the permanent Drawer variant switches to temporary below
  the `md` breakpoint, and the main content `Box` has `minWidth: 0` so it
  cannot force the page wider than the viewport. Re-check this even if a
  visual check already passed — a viewport resize during manual testing can
  mask a missing `minWidth: 0` that only shows up at specific widths.
- If your tool can render the page and capture what it looks like (a
  browser tool, an MCP browser server, a preview pane) — not just fetch HTTP
  status — do so for the home page at a standard desktop width (~1280px)
  and a mobile width (~375px). Confirm: nothing overlaps, no unintended
  horizontal scrollbar, the footer renders as specified without wrapping,
  and the logo's rendered proportions match its source file. If your tool
  cannot render/capture the page this way, do NOT tell the project leader
  layout was visually confirmed — say plainly that only functional checks
  were possible.
- After `scripts/package-app.sh` runs, confirm `<app-name>.zip` exists and
  is non-empty, and spot-check that it does NOT contain `node_modules/`,
  `.next/`, `__pycache__/`, `.venv/`, `.git/`, `.env`, `.env.local`, `.data/`,
  or `.localstorage/` — those either bloat the zip pointlessly or leak a
  real local secret/data file that should never leave this machine.

## Hard rules

- Do NOT tell the project leader the app is ready until the
  `verify-web-app.sh` / `verify-worker-app.sh` script passes, every item
  above is confirmed, AND `scripts/package-app.sh` has produced the zip.
- Loop: when you fix something, re-run the affected script.
- Report the result in plain, non-technical language, e.g.: "I built your
  app, confirmed the home page and health check both load correctly, and
  packaged everything into a zip file you can download."
