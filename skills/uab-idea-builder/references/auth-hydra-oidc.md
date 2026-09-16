# Authentication Layer — Ory Hydra OIDC

Only when login was chosen — see USERS & AUTH in `decision-matrix.md`. Every
front-facing app that needs users to log in uses this exact same pattern:
UAB's Ory Hydra OAuth2/OIDC server issues the access token, and the
`oidc-react` package drives the browser-side login flow. Never use Microsoft
Entra ID, MSAL, next-auth, or any other auth library. Skip this entire file
if the app needs no login, unless DATA SENSITIVITY forced login on. Also skip
it (auth is stubbed, not generated) whenever the EXTERNAL USERS escalation in
`decision-matrix.md` fired.

INSTALL: add `oidc-react` to `package.json` dependencies.

## `src/auth/oidcConfig.ts`

Next.js has no `import.meta.env` (Vite-only) — read `NEXT_PUBLIC_` env vars
via `process.env` instead. Two settings beyond the basics are required, both
discovered by hand-testing against UAB's real Hydra instance — not optional
polish:

```ts
export const oidcConfig = {
  authority: process.env.NEXT_PUBLIC_AUTH_URL,
  clientId: process.env.NEXT_PUBLIC_CLIENT_ID,
  redirectUri: process.env.NEXT_PUBLIC_REDIRECT_URL,
  responseType: 'code',
  scope: 'openid profile email',
  automaticSilentRenew: false,
  // oidc-react defaults autoSignIn to true, which forces every signed-out
  // visitor into an immediate full-page redirect to Hydra before any of
  // the app's own UI ever renders. Sign-in must only ever be triggered by
  // this app's own control (AuthGate's button, or the nav bar's Sign In
  // button) — never automatically — so this is false for every app that
  // uses this pattern, gated or not.
  autoSignIn: false,
  // Hydra appends ?code=...&scope=...&state=... (or ?error=...) to the
  // redirect URI on the way back from login. oidc-react processes these
  // but never removes them from the address bar, so the logged-in
  // homepage URL would otherwise show a spent authorization code. Strip it
  // via history.replaceState (not a navigation — the app is already
  // mounted and signed in at this point, so there's nothing to reload).
  onSignIn: () => {
    window.history.replaceState({}, document.title, window.location.origin);
  },
  onSignInError: () => {
    window.history.replaceState({}, document.title, window.location.origin);
  },
};
```

Do NOT add a `postLogoutRedirectUri` key here — see USING THE LOGGED-IN USER
below. Do not remove `autoSignIn`/`onSignIn`/`onSignInError` thinking they're
optional flourish; without them every generated app either auto-redirects
every visitor to Hydra on load, or leaves a spent auth code in the address
bar after every login.

## `src/auth/AuthProviderWrapper.tsx`

`oidc-react`'s `<AuthProvider>` reads `window.location` while rendering (not
inside an effect), so it cannot render during Next.js's server-side/prerender
pass — even in a `'use client'` file, since that only means the component
*can* run in the browser, not that Next.js skips rendering it on the server
first. Delay mounting the real `AuthProvider` until after the client has
hydrated, using `useSyncExternalStore` (the mounted/not-mounted value
genuinely differs between server and client — exactly what that hook is for,
and it avoids the cascading-render setState-in-effect pattern plain
`useState`+`useEffect` would need):

```tsx
'use client';
import { useSyncExternalStore, type ReactNode } from 'react';
import { AuthProvider } from 'oidc-react';
import { oidcConfig } from './oidcConfig';

const noopSubscribe = () => () => {};
function useMounted() {
  return useSyncExternalStore(noopSubscribe, () => true, () => false);
}

export default function AuthProviderWrapper({ children }: { children: React.ReactNode }) {
  const mounted = useMounted();
  if (!mounted) {
    return <>{children}</>;
  }
  return <AuthProvider {...oidcConfig}>{children}</AuthProvider>;
}
```

## `src/auth/useOptionalAuth.ts`

Because `AuthProviderWrapper` delays mounting `<AuthProvider>` until after
hydration, `oidc-react`'s own `useAuth()` hook would throw during that window
— it throws whenever there's no `<AuthProvider>` ancestor mounted yet. Every
consumer must use this small non-throwing wrapper instead, so "auth not
mounted yet" and "mounted but signed out" can both be handled the same way
via optional chaining:

```ts
'use client';
import { useContext } from 'react';
import { AuthContext } from 'oidc-react';

export function useOptionalAuth() {
  return useContext(AuthContext);
}
```

Never import or call `oidc-react`'s `useAuth()` directly anywhere in a
generated app — always use `useOptionalAuth()`.

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

  if (!auth.userData) {
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
          <Button variant="contained" size="large" onClick={() => auth.signIn()}>
            Sign in with BlazerID
          </Button>
        </Container>
      </Box>
    );
  }

  return <>{children}</>;
}
```

`!auth || auth.isLoading` must be checked before `!auth.userData` —
otherwise every fresh page load flashes this splash for a frame while
`AuthProviderWrapper` is still mounting or `oidc-react` is still processing
the redirect-back from Hydra. Never call `signIn()` automatically on mount
here — only in response to the button click; auto-redirecting on mount would
make a broken sign-out invisible (instant silent re-login, looking like
sign-out did nothing).

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
health check Container Apps uses for probes.

## Using the logged-in user

Use `useOptionalAuth()` (never `oidc-react`'s own `useAuth()`) in any client
component that needs the current user or access token
(`auth?.userData?.profile`, `auth?.userData?.access_token`).

Sign-out must call `signOutRedirect()`, never `signOut()`. `signOut()` is
only an alias for `removeUser()` — it clears this app's local copy of the
tokens but leaves Hydra's own SSO session alive, so a subsequent `signIn()`
silently re-authenticates with no prompt at all, making sign-out look like it
does nothing:

```tsx
<Button onClick={() => auth?.signOutRedirect({ post_logout_redirect_uri: '' })}>
  Sign out
</Button>
```

`post_logout_redirect_uri` must be forced to the empty string at the call
site, and must NOT be set in `oidcConfig.ts` either. Confirmed by hand against
UAB's real Hydra instance: it sits behind a CAS-integration gateway that 403s
the entire logout request whenever a `post_logout_redirect_uri` is present at
all — even a value correctly registered on the Hydra client. `oidc-react`/
`oidc-client-ts` otherwise default this value to `redirectUri` automatically,
so leaving it unset is not enough; it must be explicitly overridden to `''`
on every `signOutRedirect()` call. Trade-off: the browser is not redirected
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
ID IT must register with Ory Hydra for this app — say so in README.md.

`.env.template` still documents the same variable names (see
`env-template.md`) — for the Hydra values, the production authority (drops
the "dev" from the hostname), the same registered client ID, and the live
app's URL. These three are plain config values on the Container App, not Key
Vault secrets.
