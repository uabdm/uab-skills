# Verify & Self-Heal — deep review checklist

The project leader cannot fix code. After generating everything, you MUST
prove the app actually works before telling them it is done. `scripts/
verify-web-app.sh` / `verify-worker-app.sh` handle the mechanical
install/build/serve/curl loop (their equivalent of the old OUTPUT 7 STEPS
1–3). This file covers the judgment-based deep review — read back through
the generated code and confirm every item below. Do this in a loop and do
not stop until every step passes with zero errors; when you fix something,
re-run the affected script step.

- The generated file set matches the generation manifest emitted at the
  start of generation (see `SKILL.md`) — every file listed was actually
  written and every conditional rule fired as recorded. This is what catches
  a silently-skipped module that still builds cleanly (e.g. a missing
  `monitor.bicep`).
- (Web app) `package-lock.json` exists and is committed — NOT covered by
  `.gitignore`. `npm ci` in the Dockerfile and QA pipeline fails without it.
- `infra/modules/containerapp.bicep` tags the Container App resource with
  `'azd-service-name': 'app'` (via `union(tags, ...)`) — `azd deploy` cannot
  locate the service without it — and uses the
  `mcr.microsoft.com/azuredocs/containerapps-helloworld` placeholder image,
  never a path into the app's own (still-empty) registry.
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
  external-integration or data-store env var anywhere in the generated
  code, `.env.local`, or `.env.template` is prefixed `NEXT_PUBLIC_`.
- There are no leftover TODO stubs that would stop the app from starting
  (domain-logic TODOs are fine; broken wiring is not).
- If a login was generated, `oidcConfig.ts` has `autoSignIn: false` plus
  `onSignIn`/`onSignInError` callbacks that strip URL query params via
  `history.replaceState`, and does NOT set `postLogoutRedirectUri`.
  `AuthProviderWrapper.tsx` defers mounting `<AuthProvider>` until after
  client hydration (the `useSyncExternalStore` pattern) — a version that
  renders `<AuthProvider>` unconditionally will crash or misbehave during
  Next.js's server render. Every auth consumer imports `useOptionalAuth()`
  from `src/auth/useOptionalAuth.ts` — none import `useAuth()` from
  `oidc-react` directly. Grep the generated source for `signOut(` and
  confirm every match is actually `signOutRedirect(` — a bare `signOut()`
  call is a regression (it doesn't end the Hydra session).
- `infra/main.bicep` provisions `appInsights` and `monitor` modules, and the
  Container App params include `appInsightsConnectionString` — Application
  Insights is never optional.
- **Deploy-readiness** (each of these prevents the first `azd up`/pipeline
  run from failing — each maps to a real failure hit in a prior deploy):
  - `.dockerignore` exists at the repo root and excludes `node_modules` and
    the build-output dir (`.next`/`__pycache__`) plus `.env*`, `.data`,
    `.localstorage` (see `data-layer.md`). Without it the remote build
    ships the whole tree and either corrupts the image or leaks secrets.
  - `azure.yaml` sets `docker: remoteBuild: true`; `buildArgs` present only
    if login was chosen.
  - If login was generated: `main.bicep` declares `authUrl`, `clientId`,
    `redirectUrl` params EACH DEFAULTED TO `''` — a missing default makes
    the first provision prompt interactively and hard-fail under
    `azd up --no-prompt` in the pipelines. Confirm `main.parameters.json`
    maps the three `NEXT_PUBLIC_*` azd env values to them and
    `containerapp.bicep` forwards them to the runtime env array.
  - If Azure SQL was generated: `sql.bicep`'s firewall rule is named
    `AllowAzureServices` (NOT `AllowAllWindowsAzureIps`), and its
    `connectionString` output is ADO.NET format (`Server=tcp:...;`), never
    an `mssql://` URI. No resource name in `infra/` contains a reserved
    word.
  - `monitor.bicep`'s kind `'standard'` webtest uses the structured
    `Request` + `ValidationRules` properties, not the legacy XML
    `Configuration.WebTest` blob. Its metric alert uses `odata.type`
    `Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria`
    (`webTestId`/`componentId`/`failedLocationCount`, no `allOf`), never
    `SingleResourceMultipleMetricCriteria` — see `infra-bicep.md` for both
    schema traps.
  - (Web app) the Dockerfile is on `node:22-alpine` or newer in BOTH
    stages, and `package.json` does NOT list `better-sqlite3` — the local
    SQLite fallback uses the built-in `node:sqlite` (Node >= 22).
- If DATA SENSITIVITY (Q7) was answered A–E: PLAN.md has the compliance
  banner as its first section, README.md has the matching "Before you go
  live" section, and login is present regardless of what Q8/USERS said — if
  Q8 was answered C ("no login") but Q7 flagged sensitive data, confirm
  login was generated anyway and PLAN.md explains the override — unless the
  EXTERNAL USERS escalation applied (non-UAB audience), in which case
  confirm auth was stubbed and PLAN.md flags the IT decision instead.
- If Q6 was answered B or C: a stub integration file exists for every system
  named in the description, each with matching env var name comments in
  `.env.template`, real blank stub lines in `.env.local`, a placeholder
  secret + `containerapp.bicep` secretRef for each credential, and
  PLAN.md/README.md both list every named system with the Key Vault setup
  instructions (not a `.env.template` instruction) — confirm the count of
  stub files, Key Vault placeholders, and secretRefs all match the count of
  systems described, not just that at least one exists.
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

## Hard rules

- Do NOT tell the project leader the app is ready until the
  `verify-web-app.sh` / `verify-worker-app.sh` script passes AND every item
  above is confirmed.
- Loop: when you fix something, re-run the affected script.
- Report the result in plain, non-technical language, e.g.: "I built your
  app and opened it — the home page and health check both load correctly."
