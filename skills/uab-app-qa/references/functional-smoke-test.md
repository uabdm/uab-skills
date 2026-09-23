# Functional smoke test (Playwright)

A clean build proves the code compiles. It proves nothing about what
happens when a real browser renders and hydrates the page — that's a
separate failure class (hydration mismatches, console errors, broken
click handlers, forms that silently no-op) that only shows up by actually
running the app and interacting with it. This is the phase that would have
caught the confirmed bug that motivated this skill: a footer dialog that
built cleanly and crashed the instant a user clicked it.

## Why Playwright over a browser extension

Headless, scriptable, and gives you real `console.error`/`pageerror`
events deterministically — no dependency on a browser extension being
installed or a user granting live control of their browser each session.
`claude-in-chrome` (if connected this session) is a fine *supplement* for
eyeballing something visually, never the primary mechanism — see
`SKILL.md`.

## Setup

```
npm install -D @playwright/test
npx playwright install chromium --with-deps
```

Only Chromium is needed for a smoke test — don't install all three engines
unless something specific calls for cross-browser coverage.

## Where the test file lives

Write the spec to `.qa/smoke.spec.ts` in the app's repo root — a scratch
working location this skill owns, the same way `uab-app-creator`'s
`.verify/` is its own scratch state, not a permanent part of the shipped
app. Add `.qa/` to `.gitignore` if it isn't already covered. If the user
wants durable regression coverage kept going forward (not just a one-time
pass), say so in the Phase 5 report and offer to promote it into a real
`tests/`/`e2e/` directory — don't do that by default.

## Starting the app

Build first (Phase 2), then `npm run start` (the production server) rather
than `npm run dev` — it's what will actually run in deployment, and it
skips dev-mode-only warnings that aren't representative. Background it
(see `SKILL.md`) and poll/wait for it to report ready before running the
spec against it.

## Route discovery

Enumerate every `page.tsx` under `src/app/` (App Router) with Glob, and
map each file path to its URL path the same way Next.js does:
`src/app/page.tsx` → `/`, `src/app/about/page.tsx` → `/about`,
`src/app/blog/[slug]/page.tsx` → a dynamic segment. For a dynamic segment,
either supply one concrete sample value you know is valid (e.g. seed one
record first, if the app has a way to do that) or note in the Phase 5
report that this route was skipped and why — don't guess a URL that's
likely to 404 and call that a pass.

## Console & error capture — the core pattern

This is what actually catches the class of bug a build can't:

```ts
import { test, expect, type Page } from '@playwright/test';

async function collectPageErrors(page: Page) {
  const errors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') errors.push(msg.text());
  });
  page.on('pageerror', (err) => errors.push(err.message));
  page.on('response', (res) => {
    if (res.status() >= 500) errors.push(`${res.status()} ${res.url()}`);
  });
  return errors;
}

test('home route has no console/page errors', async ({ page }) => {
  const errors = await collectPageErrors(page);
  await page.goto('/');
  await page.waitForLoadState('networkidle');
  expect(errors, errors.join('\n')).toEqual([]);
});
```

Run this same `collectPageErrors` + navigate + `expect(errors).toEqual([])`
pattern for **every** discovered route, and again after **every**
interaction below (a click can introduce a console error a plain page load
never would — that's exactly the dialog-open bug this skill exists to
catch). A React hydration warning shows up as a `console.error` with text
like "Hydration failed" or "In HTML, `<x>` cannot be a child of `<y>`" —
don't filter these out as noise; they're precisely the signal this phase
is for.

## Interaction patterns

**Forms — happy path.** Fill every required field with a safe, valid
sample value (a plain name, a syntactically valid email, etc.), submit,
and assert the expected result actually appears (the specific text/state
change the page's own code produces — read the component to know what to
expect, don't assert something generic like "no error").

```ts
test('greeting form happy path', async ({ page }) => {
  const errors = await collectPageErrors(page);
  await page.goto('/');
  await page.getByLabel('Your Name').fill('Test User');
  await page.getByRole('button', { name: /greet me/i }).click();
  await expect(page.getByText(/hello, test user/i)).toBeVisible();
  expect(errors, errors.join('\n')).toEqual([]);
});
```

**Forms — validation path.** Submit with a required field left empty;
assert a validation state appears (an `aria-invalid`, a helper-text error
message, a `role="alert"`) rather than a silent no-op or a crash.

**Dialogs/modals.** Click every control that opens one (button text,
`aria-haspopup`, or a known trigger like the Nondiscrimination Statement
button), assert it becomes visible (`role="dialog"`) with **zero new
console errors** — this is the specific check that would have caught the
confirmed `<h2>`-in-`<h2>` bug — then close it (its own close control, or
`Escape`) and assert it's gone from the accessibility tree.

```ts
test('nondiscrimination dialog opens and closes cleanly', async ({ page }) => {
  const errors = await collectPageErrors(page);
  await page.goto('/');
  await page.getByRole('button', { name: /nondiscrimination statement/i }).click();
  const dialog = page.getByRole('dialog');
  await expect(dialog).toBeVisible();
  expect(errors, errors.join('\n')).toEqual([]);
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
});
```

**Theme toggle.** Click it, confirm no console error, and confirm some
concrete branded value actually changed (e.g. the `AppBar`'s computed
background color, or `<html>`'s color-scheme) — not just "the button
didn't crash."

**Responsive nav.** Set the viewport to a mobile width (~375px) and
confirm the permanent drawer is hidden and the hamburger opens a temporary
one; set it to a desktop width (~1280px) and confirm the permanent drawer
is visible. While at desktop width, this is also a cheap way to
mechanically verify `uab-branding`'s full-height-nav rule instead of
eyeballing a screenshot — compare the drawer's rendered height against the
viewport:

```ts
test('desktop nav fills the page height', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto('/');
  const nav = page.locator('nav.MuiDrawer-docked, [role="navigation"]').first();
  const navBox = await nav.boundingBox();
  const bodyHeight = await page.evaluate(() => document.body.scrollHeight);
  expect(navBox).not.toBeNull();
  // allow a small tolerance; the nav should track the page's scroll height,
  // not stop short at its own content height.
  expect(navBox!.height).toBeGreaterThanOrEqual(bodyHeight - 4);
});
```

## Loop

Any failure here — a console error, a hydration warning, a form that
doesn't do what its own code says it should, a dialog that doesn't open or
close cleanly, a nav that doesn't fill the page — is a real defect. Fix
it, go back to Phase 2 (rebuild), then re-run **all** of Phase 3 again, not
just the one test that failed — a fix in a shared component (the theme,
the AppShell, a form field) can affect routes you already passed.
