# Project Scaffold — Web application (Next.js + MUI)

Used when Q4 (visual interface) = "Yes" or "Not sure" — see
`decision-matrix.md`. Generate a working "hello world" level Next.js
application using the App Router (`src/app/`). All pages should render
without error and display the app name and a brief description.

## Package versioning

At generation time, resolve every npm dependency to its current stable
version and write a caret range in `package.json` (e.g.
`"@mui/material": "^7.2.0"`, `"next": "^16.1.0"`) — NEVER the literal string
`"latest"`. `"latest"` means two apps generated a month apart land on
different majors, and a rebuild after `node_modules` loss can silently jump
a major and break the build. After install, `package-lock.json` MUST exist
and be committed (never gitignored) — `npm ci` in the Dockerfile and the QA
pipeline hard-fails without it (see `scripts/push-to-develop.sh` and
`verification-checklist.md`).

## Folder structure

```
./                               ← repo root
├── src/
│   ├── app/
│   │   ├── layout.tsx           ← wraps entire app in UABThemeProvider + CssBaseline
│   │   ├── page.tsx             ← home page stub with app name and description
│   │   └── api/
│   │       └── health/
│   │           └── route.ts     ← GET /api/health → { status: "ok", app: "<name>" }
│   ├── auth/                    ← only if login was chosen (see auth-hydra-oidc.md)
│   │   ├── oidcConfig.ts
│   │   ├── AuthProviderWrapper.tsx
│   │   ├── useOptionalAuth.ts
│   │   └── AuthGate.tsx         ← only if Q3 = "Our team / staff only"
│   ├── components/
│   │   └── layout/
│   │       ├── AppShell.tsx     ← MUI AppBar (always UAB Green) + nav + Footer
│   │       ├── Footer.tsx       ← standard UAB footer, same on every generated app
│   │       └── ThemeToggle.tsx  ← icon button that toggles light/dark
│   ├── lib/
│   │   └── config.ts            ← loads all env vars; throws on missing required vars
│   └── theme/
│       ├── LightTheme.js        ← from branding-theme.md
│       ├── DarkTheme.js         ← from branding-theme.md
│       └── ThemeProvider.tsx    ← see below
├── public/
├── tests/
│   └── health.test.ts           ← minimal smoke test, see below
├── Dockerfile
├── .dockerignore                ← see data-layer.md
├── package.json                 ← Next.js + MUI + deps as resolved caret ranges
├── next.config.js
├── .gitignore                   ← see data-layer.md
├── .env.local                   ← generated whenever login, a data store, or an
│                                    integration was chosen — see auth-hydra-oidc.md
│                                    and decision-matrix.md
├── .env.template                ← see env-template.md
├── azure-pipelines-dev.yml      ← see pipelines-azure-devops.md
├── azure-pipelines-qa.yml
├── azure-pipelines-prod.yml
├── azure.yaml                   ← see azure-yaml.md
├── infra/                       ← see infra-bicep.md
└── README.md                    ← see readme-template.md
```

## ThemeProvider (`src/theme/ThemeProvider.tsx`)

React context-based theme provider: reads OS preference with
`useMediaQuery('(prefers-color-scheme: dark)')`, defaults to it on first
load, exposes `{ mode, toggleMode }` via a `ThemeContext`, wraps children in
MUI `ThemeProvider` with the correct theme object, wraps `CssBaseline`
inside the provider. Export: `UABThemeProvider` (default) and `useUABTheme`.

```tsx
'use client';
import React, { createContext, useContext, useState } from 'react';
import { ThemeProvider } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';
import useMediaQuery from '@mui/material/useMediaQuery';
import { LightTheme } from './LightTheme';
import { DarkTheme } from './DarkTheme';

const ThemeContext = createContext({ mode: 'light', toggleMode: () => {} });
export const useUABTheme = () => useContext(ThemeContext);

export default function UABThemeProvider({ children }) {
  const prefersDark = useMediaQuery('(prefers-color-scheme: dark)');
  const [mode, setMode] = useState(prefersDark ? 'dark' : 'light');
  const toggleMode = () => setMode(m => m === 'light' ? 'dark' : 'light');
  return (
    <ThemeContext.Provider value={{ mode, toggleMode }}>
      <ThemeProvider theme={mode === 'dark' ? DarkTheme : LightTheme}>
        <CssBaseline />
        {children}
      </ThemeProvider>
    </ThemeContext.Provider>
  );
}
```

## Layout (`src/app/layout.tsx`)

Import `AppRouterCacheProvider` from `@mui/material-nextjs` (use the current
subpath for the installed Next.js major, e.g.
`'@mui/material-nextjs/v16-appRouter'`). REQUIRED for MUI to work correctly
with the App Router — omitting it causes hydration and module errors at
runtime. It must wrap `UABThemeProvider`, not the reverse.

No login:
```tsx
<AppRouterCacheProvider>
  <UABThemeProvider>{children}</UABThemeProvider>
</AppRouterCacheProvider>
```

Login, Q3 = "Our team / staff only" (nest AuthGate so nothing renders pre-login):
```tsx
<AppRouterCacheProvider>
  <AuthProviderWrapper>
    <UABThemeProvider>
      <AuthGate>
        <AppShell>{children}</AppShell>
      </AuthGate>
    </UABThemeProvider>
  </AuthProviderWrapper>
</AppRouterCacheProvider>
```

Login, every other Q3 answer (omit AuthGate):
```tsx
<AppRouterCacheProvider>
  <AuthProviderWrapper>
    <UABThemeProvider>
      <AppShell>{children}</AppShell>
    </UABThemeProvider>
  </AuthProviderWrapper>
</AppRouterCacheProvider>
```

Omit `AuthProviderWrapper` entirely (and the whole `src/auth/` folder) when
no login is needed.

Include a TODO comment for the Typekit font embed:
```tsx
{/* TODO: Add your Adobe Typekit embed code here for kulturista-web
    and proxima-nova fonts. Without it, the UAB brand fonts will not
    load and the app will fall back to system sans-serif. */}
```

## AppShell (`src/components/layout/AppShell.tsx`)

- MUI AppBar at the top, ALWAYS a fixed UAB Green background — use
  `theme.palette.primary.main`, never `theme.palette.background.paper` or
  any other mode-dependent color. The bar must look identical in light and
  dark mode; only the page content below it changes with the theme toggle.
- Logo: use `/uab-logo-white.png` (see `branding-theme.md` for how it gets
  there), positioned top-left of the AppBar toolbar. Use a plain `<img>` —
  never `next/image` here, since its required width/height props are easy
  to set to a ratio that doesn't match the real file, which stretches or
  squishes the logo. Style it with exactly:
  ```tsx
  <img src="/uab-logo-white.png" alt="UAB" style={{ maxWidth: 270, height: 'auto', display: 'block' }} />
  ```
  Never set a fixed `height` anywhere on this element alongside `maxWidth`
  or `width` — `height` must stay `'auto'`, or the browser stretches the
  image to fill both constraints, which is what makes a logo look
  squished. Never swap in a different logo variant for dark mode.
- Because the AppBar's background never changes with the theme, every
  element inside it (app name text, nav links, ThemeToggle, sign-in/out
  control) must be given an explicit light/white color rather than
  inheriting the ambient `theme.palette.text.primary` — that flips between
  light and dark mode and would go low-contrast or invisible against the
  green bar in one of the two modes. Cross-check white-on-UAB-Green against
  the COLOR ACCESSIBILITY page (`branding-theme.md`) before finalizing.
- Navigation: derive from the user's description of what the app does. If
  they listed distinct sections or actions, add nav items for each. If it's
  a simple single-purpose tool, use a minimal top bar only.
- Use MUI Drawer for sidebar if 4+ nav items; top nav links if 3 or fewer.
  A Drawer is NOT sufficient on its own — MUI positions it outside normal
  document flow by default, so without the layout below it floats over the
  page instead of pushing content aside. Build the Drawer and the content
  area as flex siblings so the browser handles the offset automatically,
  rather than hand-computing a `marginLeft` that has to stay in sync with a
  separate width value:

  ```tsx
  const drawerWidth = 260;

  // ...inside AppShell, below the AppBar:
  <Box sx={{ display: 'flex', flexGrow: 1 }}>
    {isDesktop ? (
      <Drawer
        variant="permanent"
        sx={{
          width: drawerWidth,
          flexShrink: 0,
          '& .MuiDrawer-paper': {
            width: drawerWidth,
            boxSizing: 'border-box',
            position: 'static', // stays in flex flow — no overlap, no
                                 // separate marginLeft to keep in sync
          },
        }}
      >
        {navContent}
      </Drawer>
    ) : (
      <Drawer
        variant="temporary"
        open={mobileOpen}
        onClose={() => setMobileOpen(false)}
      >
        {navContent}
      </Drawer>
    )}
    <Box component="main" sx={{ flexGrow: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
      <Box sx={{ flexGrow: 1, p: 3 }}>{children}</Box>
      <Footer />
    </Box>
  </Box>
  ```

  `isDesktop` comes from `useMediaQuery(theme.breakpoints.up('md'))`; below
  `md`, render a hamburger `IconButton` in the AppBar (styled white, like
  the other AppBar controls) that toggles `mobileOpen` for the temporary
  Drawer. `navContent` is the same nav list shared by both Drawer variants.
  `minWidth: 0` on the main content Box is required — without it, a flex
  child can refuse to shrink below its content's natural width and force
  the whole row (Drawer + content) wider than the viewport, producing an
  unwanted horizontal scrollbar.
- If login was chosen, add a sign-in/sign-out control via
  `useOptionalAuth()` — never `react-oidc-context`'s own `useAuth()`. For Q3 =
  "Our team / staff only", AppShell only ever renders already inside
  AuthGate, so show just a "Sign out" button with the user's name/email.
  For every other Q3 answer, show "Sign in" when signed out and "Sign out"
  when signed in.
- Render `Footer.tsx` inside the same content column as `{children}` (see
  the Drawer layout snippet above) — not wired separately into
  `layout.tsx`. Since every login configuration already nests AppShell
  around `{children}`, putting Footer inside AppShell's content column
  guarantees it appears on every page, including pages inside AuthGate for
  staff-only apps, with no separate wiring per branch, and it inherits the
  same Drawer offset as the rest of the page content automatically.

## Footer (`src/components/layout/Footer.tsx`)

Every generated app gets the exact same standard UAB footer — a fixed
platform requirement, not derived from the project leader's answers. Adapt
UAB's existing production footer pattern (MyUABPortal's Footer component) to
this Next.js + TypeScript + MUI scaffold:

- A footer landmark (`component="footer"`) styled with
  `theme.palette.background.default`, so — unlike the AppBar — it DOES
  follow light/dark mode.
- Responsive via `useMediaQuery(theme.breakpoints.down('sm'))`:
  - Mobile: a two-column stacked grid — Nondiscrimination Statement button
    and Contact UAB link in one column; Privacy, Terms of Use, and the
    copyright line in the other.
  - Desktop: a single centered row, in order — Nondiscrimination Statement
    button, Contact UAB, Privacy, Terms of Use, copyright line.
- Links (use exactly these — do not invent, omit, or add others):
  - Contact UAB → https://www.uab.edu/home/contact
  - Privacy → https://www.uab.edu/privacy/statements
  - Terms of Use → https://www.uab.edu/toolkit/web/terms-of-use
  - Do NOT include an A-Z Site Index link — these generated apps
    intentionally omit it.
- Copyright line: "© \<current year, computed via
  `new Date().getFullYear()`\> The University of Alabama at Birmingham"
- Nondiscrimination Statement: a button (a contained/filled button, styled
  distinctly from the plain text links) that opens an MUI Dialog with a
  close IconButton (top-right, CloseIcon) in addition to standard
  backdrop/Escape dismissal. Use this exact title and body — do not
  paraphrase, shorten, or summarize it:

  > **Title:** Nondiscrimination Statement
  >
  > **Body:** UAB is an Equal Employment/Equal Educational Opportunity
  > Institution dedicated to providing equal opportunities and equal access
  > to all individuals regardless of race, color, religion, ethnic or
  > national origin, sex (including pregnancy), genetic information, age,
  > disability, and veteran's status. As required by Title IX, UAB
  > prohibits sex discrimination in any education program or activity that
  > it operates. Individuals may report concerns or questions to UAB's
  > Assistant Vice President and Senior Title IX Coordinator. The Title IX
  > notice of nondiscrimination is located at uab.edu/titleix.

  Render "uab.edu/titleix" as a link to https://uab.edu/titleix
  (`target="_blank"`, `rel="noopener noreferrer"`).

## Page stubs

If the project leader described distinct things users can do (Q5), generate
one page per major action (e.g. "upload a file" → `src/app/upload/page.tsx`).
Each page stub should show the page title and a placeholder content area
with a TODO comment.

## Smoke test (`tests/health.test.ts`)

Generate exactly one minimal test so test-runner plumbing exists from day
one (the Python layout already ships `tests/test_health.py`; the web layout
must not ship zero tests). Use vitest (devDependency) with a
`"test": "vitest run"` script in `package.json`. The test imports the health
Route Handler directly — no running server needed:

```ts
import { GET } from '../src/app/api/health/route';
const res = await GET();
expect(res.status).toBe(200);
expect(await res.json()).toMatchObject({ status: 'ok' });
```

The QA pipeline runs it (see `pipelines-azure-devops.md`).

## Dockerfile

Multi-stage build. Stage 1 installs the FULL dependency set — a TypeScript
Next.js build needs typescript/@types even though they're never used at
runtime, so `npm ci --only=production` before `npm run build` can never
work. Stage 2 is the slim runtime image with production deps only.

```dockerfile
# TODO: Replace with the current stable node slim tag from hub.docker.com
# before deploying to production. Verify the tag is current.
# MINIMUM Node 22 — the local dev fallback uses the built-in node:sqlite
# module (see data-layer.md), which is only available on Node >= 22. Do not
# drop below node:22-alpine.

# ── Stage 1: build ────────────────────────────────────────────────────
FROM node:22-alpine AS build
WORKDIR /app
# NEXT_PUBLIC_* values are inlined into the browser bundle AT BUILD TIME, so
# they must arrive here as build args (see azure-yaml.md's docker.buildArgs
# and the pipeline variable groups) for the client-side login flow to work.
# IMPORTANT: build args alone are NOT enough. Any server-side code that reads
# these values at request time — e.g. the API route token verifier, which
# reads NEXT_PUBLIC_AUTH_URL / NEXT_PUBLIC_CLIENT_ID from process.env to reach
# Hydra's discovery/JWKS — needs them as Container App RUNTIME env vars too.
# Next.js only inlines a STATIC `process.env.NEXT_PUBLIC_X`; a dynamic
# `process.env[name]` lookup (as a typed config helper uses) stays a real
# runtime read, and the runtime container won't have the value unless it's set
# as a runtime env var. So these are delivered BOTH ways: as build args here
# AND as runtime env on the Container App (see infra-bicep.md). Omit all of
# this if the app has no login.
ARG NEXT_PUBLIC_AUTH_URL
ARG NEXT_PUBLIC_CLIENT_ID
ARG NEXT_PUBLIC_REDIRECT_URL
ENV NEXT_PUBLIC_AUTH_URL=$NEXT_PUBLIC_AUTH_URL
ENV NEXT_PUBLIC_CLIENT_ID=$NEXT_PUBLIC_CLIENT_ID
ENV NEXT_PUBLIC_REDIRECT_URL=$NEXT_PUBLIC_REDIRECT_URL
COPY package*.json ./
# npm ci requires the committed package-lock.json (see PACKAGE VERSIONING);
# fall back to npm install only if the lockfile is somehow missing.
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi
COPY . .
RUN npm run build

# ── Stage 2: runtime ──────────────────────────────────────────────────
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN if [ -f package-lock.json ]; then npm ci --omit=dev; else npm install --omit=dev; fi
COPY --from=build /app/.next ./.next
COPY --from=build /app/public ./public
COPY --from=build /app/next.config.js ./next.config.js
USER node
EXPOSE 3000
CMD ["npm", "start"]
```

## package.json dependencies

Resolved caret ranges — see PACKAGE VERSIONING above; never `"latest"`:

- `@mui/material`, `@mui/icons-material`, `@emotion/react`,
  `@emotion/styled`, `@emotion/cache`, `@mui/material-nextjs`
- `next`, `react`, `react-dom`
- `typescript`, `@types/react`, `@types/node` — REQUIRED, the TypeScript
  build fails without these; the Dockerfile's build stage installs the full
  dependency set specifically so they're present at build time.
- `vitest` as a devDependency plus a `"test": "vitest run"` script (see
  smoke test above).
- `react-oidc-context` and its peer `oidc-client-ts` if login is needed
  (`auth-hydra-oidc.md`) — both required, `react-oidc-context` is a thin
  wrapper. Peer range `react: >=16.14.0`, so this resolves cleanly against
  current-stable React; no version pin needed for auth's sake.
- `@azure/storage-blob` if Blob Storage is needed.
- `@azure/identity` for Key Vault access.
- SQL data layer deps if Azure SQL is needed (`data-layer.md`): `mssql`
  (talks to Azure SQL). The zero-config LOCAL fallback uses Node's built-in
  `node:sqlite` — it needs NO dependency and NO `@types` package, so do NOT
  add `better-sqlite3` or `@types/better-sqlite3`. (`node:sqlite` requires
  Node >= 22 — keep the Dockerfile on `node:22-alpine`.)
