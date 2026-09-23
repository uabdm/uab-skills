# Landmarks, skip link, heading hierarchy

Source of truth: `MyUABPortal/src/Containers/Portal/Top/Top.js`,
`Center/Content/Contentv2.js`, `Bottom/Footer/Footer.js`.

## Landmark regions (WCAG 2.1 AA, SC 1.3.1 / 2.4.1)

All via MUI's `component=` prop — never raw HTML landmark tags mixed in
ad hoc, and never left as a bare `<div>`/`<Box>` with no `component=`.

| Region | Pattern |
|---|---|
| Header | `<AppBar component="header" position="fixed" ...>` |
| Main content | `<Box component="main" role="main" id="main-content" tabIndex={-1} ...>` |
| Nav | `<Box component="nav" aria-label="Primary <app name> navigation" ...>` (or on the `Drawer`'s content wrapper) |
| Footer | `<Box component="footer" ...>` (already true of `footer-template.md`'s template) |

`role="main"` is redundant with `component="main"` in most browsers but
costs nothing and matches the portal exactly — keep it.

This is a **currently-missing gap** in the existing app-creator's
`AppShell.tsx` output (confirmed by reading `timeoff-demo-app-slim-litelllm`'s
generated `AppShell.tsx`: the `AppBar` has no `component="header"`, the
content `Box` has no `component="main"`, and the nav `List`/`Drawer` has no
`component="nav"` or `aria-label`) — apply all four explicitly when
generating a new `AppShell.tsx`.

## Skip link (WCAG 2.1 AA, SC 2.4.1 Bypass Blocks)

Source: `MyUABPortal/src/Containers/Portal/Top/Top.js:52-67,75`. A real,
working pattern — visually hidden off-screen until keyboard-focused, then
slides into view:

```tsx
// First child rendered in the app shell, before the AppBar.
<Box
  component="a"
  href="#main-content"
  sx={{
    position: 'absolute',
    left: (theme) => theme.spacing(2),
    top: '-100px',
    zIndex: (theme) => theme.zIndex.modal + 1,
    padding: (theme) => theme.spacing(1, 2),
    backgroundColor: 'background.paper',
    color: 'text.primary',
    textDecoration: 'none',
    borderRadius: 1,
    '&:focus-visible': {
      top: (theme) => theme.spacing(1),
      outline: (theme) => `3px solid ${theme.palette.primary.main}`,
      outlineOffset: '2px',
    },
  }}
>
  Skip to main content
</Box>
```

Its target is the `id="main-content"` main-content `Box` described above,
with `tabIndex={-1}` so it's programmatically focusable via the skip link
without also being reachable by ordinary Tab-key navigation (which would
put an empty extra stop in the tab order on every page).

This is **entirely absent** from the current generated app — a hard WCAG
2.4.1 gap. Every generated `AppShell.tsx` must include this as its first
rendered element, before the AppBar.

## Heading hierarchy (WCAG 2.1 AA, SC 1.3.1)

MUI's `variant`/`component` decoupling is the load-bearing pattern: visual
size (`variant`) and semantic level (`component`) are set independently.
**Exactly one real `<h1>` per page** — the visible page/app title —
regardless of what `variant` looks best for it:

```tsx
<Typography variant="h4" component="h1">Welcome!</Typography>
```

Section headings inside a page, drawer, dialog, or panel use `component="h2"`;
sub-sections use `component="h3"`. Never rely on `Typography`'s default
`variant`→`component` mapping (e.g. a bare `variant="h4"` silently renders
an actual `<h4>` with no `component` override) — that's exactly the gap
found in `timeoff-demo-app-slim-litelllm`'s `page.tsx`, which used
`variant="h4"` with no `component="h1"`, so the page has no real `<h1>` at
all.

## Audit-mode check

- Grep `AppShell.tsx`/`layout.tsx` for `component="header"`,
  `component="main"`, `component="nav"`, `component="footer"` — flag any
  missing.
- Grep for `id="main-content"` and `tabIndex={-1}` on the main region, and
  for a `href="#main-content"` skip link as the first rendered element.
- Grep every page/route's top-level `Typography` for a `component="h1"` —
  flag a page with no `<h1>` at all, or more than one.
