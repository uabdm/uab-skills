# Authentication Layer — Ory Hydra OIDC

Only when login was chosen — see USERS & AUTH in `decision-matrix.md`. Every
front-facing app that needs users to log in uses this exact same pattern:
UAB's Ory Hydra OAuth2/OIDC server issues the access token, and the
`react-oidc-context` package (a thin wrapper around `oidc-client-ts`) drives
the browser-side login flow. Never use `oidc-react` (no release has a peer
range that cleanly supports React 19 — even its newest 4.0.1 only bumps the
`react` peer to `^19.0.0` while leaving `react-dom`'s peer stuck at
`^18.0.0`, an inconsistency in the package itself that still ERESOLVEs
against a React 19 app), Microsoft Entra ID, MSAL, next-auth, or any other
auth library. Skip this entire file if the app needs no login, unless DATA
SENSITIVITY forced login on. Also skip it (auth is stubbed, not generated)
whenever the EXTERNAL USERS escalation in `decision-matrix.md` fired.

INSTALL: add both `react-oidc-context` and its peer `oidc-client-ts` to
`package.json` dependencies — `react-oidc-context` only wraps
`oidc-client-ts`'s `UserManager`, it does not bundle it. Its peer range is
`react: >=16.14.0`, so it resolves cleanly against current-stable React with
no version pin or `--legacy-peer-deps` needed.

## `src/auth/oidcConfig.ts`

Next.js has no `import.meta.env` (Vite-only) — read `NEXT_PUBLIC_` env vars
via `process.env` instead. `react-oidc-context` passes this object straight
through to `oidc-client-ts`'s `UserManager`, so field names follow
`oidc-client-ts`'s convention (snake_case for actual OIDC wire params,
camelCase for library behavior flags) — do NOT use `oidc-react`'s old
camelCase names (`clientId`, `redirectUri`, `responseType`) for those three,
they're silently ignored by `oidc-client-ts` rather than erroring:

```ts
export const oidcConfig = {
  authority: process.env.NEXT_PUBLIC_AUTH_URL,
  client_id: process.env.NEXT_PUBLIC_CLIENT_ID,
  redirect_uri: process.env.NEXT_PUBLIC_REDIRECT_URL,
  response_type: 'code',
  scope: 'openid profile email',
  automaticSilentRenew: false,
  // Hydra appends ?code=...&scope=...&state=... to the redirect URI on the
  // way back from a SUCCESSFUL login. onSigninCallback fires right after
  // react-oidc-context's AuthProvider processes that — strip the params via
  // history.replaceState (not a navigation — the app is already mounted and
  // signed in at this point, so there's nothing to reload). This does NOT
  // fire on a failed/?error=... redirect back from Hydra — that's handled
  // separately in AuthProviderWrapper.tsx, see the comment there.
  onSigninCallback: () => {
    window.history.replaceState({}, document.title, window.location.pathname);
  },
};
```

There is no `autoSignIn` setting to disable here — unlike `oidc-react`,
`react-oidc-context`'s `AuthProvider` never redirects an unauthenticated
visitor to Hydra on its own; it only processes an already-in-flight
callback or an existing session. Automatic sign-in-on-mount is strictly
opt-in (the library's own `useAutoSignin()` hook), so simply never calling
it keeps sign-in gated behind this app's own control (AuthGate's button, or
the nav bar's Sign In button) with nothing extra to configure.

Do NOT add a `post_logout_redirect_uri` key here — see USING THE LOGGED-IN
USER below. Do not remove `onSigninCallback` thinking it's optional
flourish; without it every generated app leaves a spent auth code in the
address bar after every successful login.

## `src/auth/AuthProviderWrapper.tsx`

Unlike `oidc-react`, `react-oidc-context`'s `<AuthProvider>` only touches
`window`/`location` inside a `useEffect` (guarded by a `typeof window`
check for the one synchronous reference), never during render — so it
renders identically on the server and on first client render, with no
hydration-delay trick needed. Mount it directly:

```tsx
'use client';
import { useEffect, type ReactNode } from 'react';
import { AuthProvider, useAuth } from 'react-oidc-context';
import { oidcConfig } from './oidcConfig';

// oidcConfig.ts's onSigninCallback only fires after a SUCCESSFUL
// signinCallback() — react-oidc-context throws before that callback ever
// runs when Hydra redirects back with ?error=... instead of ?code=...,
// which would otherwise leave the spent ?error=&state= params sitting in
// the address bar. This effect is the other half of that URL cleanup, for
// the failure path.
function AuthErrorUrlCleanup() {
  const auth = useAuth();
  useEffect(() => {
    if (auth.error) {
      window.history.replaceState({}, document.title, window.location.pathname);
    }
  }, [auth.error]);
  return null;
}

export default function AuthProviderWrapper({ children }: { children: ReactNode }) {
  return (
    <AuthProvider {...oidcConfig}>
      <AuthErrorUrlCleanup />
      {children}
    </AuthProvider>
  );
}
```

## `src/auth/useOptionalAuth.ts`

`react-oidc-context`'s own `useAuth()` never throws outside a mounted
`<AuthProvider>` (it warns to the console and returns `undefined`), so
nothing here is working around a hazard the way the old `oidc-react` version
was — this file exists purely to keep one single, consistent import path for
auth state across every generated app, via the same `useContext(AuthContext)`
pattern:

```ts
'use client';
import { useContext } from 'react';
import { AuthContext } from 'react-oidc-context';

export function useOptionalAuth() {
  return useContext(AuthContext);
}
```

Never import or call `react-oidc-context`'s `useAuth()` directly anywhere in
a generated app — always use `useOptionalAuth()`.

## `src/auth/AuthGate.tsx` (ONLY when Q3 = "Our team / staff only")

For internal-only apps, nothing — no nav, no page content — should ever
render before a signed-in user is confirmed. This sits in front of the whole
app, inside `AuthProviderWrapper` and `UABThemeProvider` (so the splash is
themed and branded):

```tsx
'use client';
import type { ReactNode } from 'react';
import Box from '@mui/material/Box';
import Container from '@mui/material/Container';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import CircularProgress from '@mui/material/CircularProgress';
import { useOptionalAuth } from './useOptionalAuth';

export default function AuthGate({ children }: { children: ReactNode }) {
  const auth = useOptionalAuth();

  if (!auth || auth.isLoading) {
    return (
      <Box sx={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 2 }}>
        <CircularProgress />
        <Typography color="text.secondary">Checking your sign-in status…</Typography>
      </Box>
    );
  }

  if (!auth.user) {
    return (
      <Box sx={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center', px: 2 }}>
        <Container maxWidth="xs" sx={{ textAlign: 'center' }}>
          {/* Use assets/uabCoreLogoWhiteSmall.png (bundled with this skill —
              see branding-theme.md). This Box sits on
              theme.palette.background.default, which is light in light
              mode, so wrap the logo in a small UAB Green
              (theme.palette.primary.main) panel here for contrast. The top
              nav bar doesn't need this wrapper since its background is
              always UAB Green. */}
          <Typography variant="h4" component="h1" sx={{ mb: 1 }}>{/* <App Name> */}</Typography>
          <Typography variant="body1" color="text.secondary" sx={{ mb: 4 }}>
            Sign in with your UAB BlazerID to continue.
          </Typography>
          <Button variant="contained" size="large" onClick={() => auth.signinRedirect()}>
            Sign in with BlazerID
          </Button>
        </Container>
      </Box>
    );
  }

  return <>{children}</>;
}
```

`!auth || auth.isLoading` must be checked before `!auth.user` — otherwise
every fresh page load flashes this splash for a frame while
`react-oidc-context` is still processing the redirect-back from Hydra.
Never call `signinRedirect()` automatically on mount here — only in
response to the button click; auto-redirecting on mount would make a broken
sign-out invisible (instant silent re-login, looking like sign-out did
nothing).

Skip this file entirely for Q3 answers "Our customers" / "Both" / "Not sure"
— those apps keep the optional sign-in control in the nav bar and render
their pages regardless of auth state.

## Wiring it up

See the LAYOUT spec in `scaffold-web-nextjs.md` for the exact
`src/app/layout.tsx` nesting order. Internal-only apps nest `AuthGate`
directly around `AppShell` so nothing in the nav or the page renders
pre-login; all other apps with login omit `AuthGate` and render `AppShell`
directly.

Note: `app/api/health/route.ts` is a Route Handler, not a page — it never
passes through `layout.tsx`'s React tree, so `AuthGate` never blocks the
health check endpoint used to verify the app is running.

## Using the logged-in user

Use `useOptionalAuth()` (never `react-oidc-context`'s own `useAuth()`) in any
client component that needs the current user or access token
(`auth?.user?.profile`, `auth?.user?.access_token`).

Sign-out must call `signoutRedirect()`, never `removeUser()` alone.
`removeUser()` only clears this app's local copy of the tokens but leaves
Hydra's own SSO session alive, so a subsequent `signinRedirect()` silently
re-authenticates with no prompt at all, making sign-out look like it does
nothing:

```tsx
<Button onClick={() => auth?.signoutRedirect({ post_logout_redirect_uri: '' })}>
  Sign out
</Button>
```

`post_logout_redirect_uri` must be forced to the empty string at the call
site, and must NOT be set in `oidcConfig.ts` either. Confirmed by hand against
UAB's real Hydra instance: it sits behind a CAS-integration gateway that 403s
the entire logout request whenever a `post_logout_redirect_uri` is present at
all — even a value correctly registered on the Hydra client. `oidc-client-ts`
otherwise defaults this value to `redirect_uri` automatically, so leaving it
unset is not enough; it must be explicitly overridden to `''` on every
`signoutRedirect()` call. Trade-off: the browser is not redirected
back into the app after logout — the user lands on Hydra/CAS's own
logged-out page and navigates back manually. This matches how UAB's other
production apps (e.g. MyUABPortal) already behave, and means IT does not need
to register a post-logout redirect URI on the Hydra client at all — do not
add that as a setup step.

## `.env.local` — Hydra auth values (only when login was chosen)

Generate this file with REAL, working values, not placeholders. Unlike a
database or storage connection string, none of these three values are secret
and all three are fully knowable at generation time, so local dev logs in
with zero extra setup:

```
NEXT_PUBLIC_AUTH_URL=https://<frontdoor-dev>/auth2/public/
NEXT_PUBLIC_CLIENT_ID=<app-name-lowercase-hyphenated>
NEXT_PUBLIC_REDIRECT_URL=http://localhost:3000
```

Derive `NEXT_PUBLIC_CLIENT_ID` from the project name (Q1): lowercase, spaces
become hyphens (e.g. "Spark Ideas" → "spark-ideas"). This is also the client
ID whoever deploys this app for real must register with Ory Hydra — say so
in README.md.

`.env.template` still documents the same variable names (see
`env-template.md`) as placeholders for whatever real deployment this app
eventually gets — the authority, the registered client ID, and that
deployment's URL. These three are plain config values, never secrets, so a
placeholder here is fine; only the LOCAL values in `.env.local` need to be
real and working.
