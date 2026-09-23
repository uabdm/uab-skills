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
| Nav | `component="nav"` **and** `aria-label="Primary <app name> navigation"` passed directly as props on the `<Drawer>` itself — never on a wrapping `<Box>` around the `Drawer`. See "Permanent nav must fill full page height" below for why. |
| Footer | `<Box component="footer" ...>` (already true of `footer-template.md`'s template) |

`role="main"` is redundant with `component="main"` in most browsers but
costs nothing and matches the portal exactly — keep it.

This is a **currently-missing gap** in the existing app-creator's
`AppShell.tsx` output (confirmed by reading `timeoff-demo-app-slim-litelllm`'s
generated `AppShell.tsx`: the `AppBar` has no `component="header"`, the
content `Box` has no `component="main"`, and the nav `List`/`Drawer` has no
`component="nav"` or `aria-label`) — apply all four explicitly when
generating a new `AppShell.tsx`.

## Permanent nav must fill full page height, every time, at any content length

A permanent `Drawer` on desktop must visually extend all the way down the
page — its `background.paper` fill shouldn't stop partway down and expose
raw `background.default` beneath it, regardless of how few nav items exist
or how short the page's main content is. Confirmed bug in a generated app
(`uab-app-creator-nobrand-hello-world-brand-uabgreen`): the nav `Drawer`
was cut off at the height of its own "Home" list item instead of reaching
the bottom of the viewport.

Two things are both required, verified directly against
`@mui/material/Drawer/Drawer.js`:

1. **`component="nav"` goes directly on `<Drawer>`, never on a wrapping
   `<Box component="nav">` around it.** MUI's `DrawerPaper` has
   `height: '100%'` baked in unconditionally, and for `variant="permanent"`
   the docked root (`DrawerDockedRoot`, a `styled('div', ...)`) receives
   `component`/`aria-label` through its own prop passthrough — so
   `<Drawer component="nav" aria-label="...">` retags that *same* flex
   item to `<nav>` without adding an extra element. A `height: 100%` only
   resolves against a containing block with a *definite* computed height.
   If you instead wrap `Drawer` in `<Box component="nav">`, that Box (not
   the Drawer) becomes the flex item that gets stretched by the row's
   `align-items: stretch` — the Drawer inside it is just a plain block
   child with no stretch of its own, so its `height: 100%` resolves
   against the Box's *content* height, not the stretched height, and the
   Drawer silently shrinks back to fitting only its own items.
2. **The row containing the `Drawer` and the main-content `Box` needs
   `flexGrow: 1`** (on top of `display: 'flex'`), and that row must itself
   be a child of an outer `Box` with `display: 'flex', flexDirection:
   'column', minHeight: '100vh'`. Without `flexGrow: 1` on the row, the row
   only grows to fit its content's natural height instead of stretching to
   fill the remaining viewport — so even a correctly-placed `component="nav"`
   Drawer only stretches to match a short main-content column instead of
   the full page. This same `flexGrow: 1` is also what pins the footer to
   the bottom of the viewport on short pages (a sticky-footer side effect,
   not a separate rule).

```tsx
// Correct — Drawer is the direct flex child, row has flexGrow: 1.
<Box sx={{ display: 'flex', flexDirection: 'column', minHeight: '100vh' }}>
  {/* skip link, AppBar (position="fixed", out of flow) */}
  <Box sx={{ display: 'flex', flexGrow: 1, mt: 8 }}>
    <Drawer
      component="nav"
      aria-label="Primary <app name> navigation"
      variant={isDesktop ? 'permanent' : 'temporary'}
      sx={{
        width: drawerWidth,
        flexShrink: 0,
        '& .MuiDrawer-paper': { width: drawerWidth, boxSizing: 'border-box', position: 'static' },
      }}
    >
      {navContent}
    </Drawer>
    <Box component="main" role="main" id="main-content" tabIndex={-1} sx={{ flexGrow: 1, minWidth: 0, display: 'flex', flexDirection: 'column' }}>
      <Box sx={{ flexGrow: 1, p: 3 }}>{children}</Box>
      <Footer />
    </Box>
  </Box>
</Box>
```

### Top spacing inside the nav, below the AppBar

Give `navContent` more top breathing room than a reflexive body padding
value — a nav item sitting flush against the green AppBar reads as broken
even when the layout above is structurally correct. Confirmed feedback on
a generated app: `p: 2` (16px) uniformly was too tight between the AppBar
and the first nav item. Use an asymmetric padding with a larger top value
instead of bumping all sides:

```tsx
const navContent = (
  <Box sx={{ px: 2, pb: 2, pt: 4 }}>
    <Typography variant="h6" sx={{ color: 'text.primary', mb: 2 }}>Navigation</Typography>
    {/* nav items */}
  </Box>
);
```

If using a `<Toolbar />` spacer inside the `Drawer` instead of `mt: 8` on
the row (both are valid ways to sit the nav content below the fixed
AppBar — pick one, don't combine them), add the same extra top padding on
the `Box` that follows the spacer rather than relying on the spacer's
height alone: `<Box sx={{ overflow: 'auto', pt: 2 }}>`.

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
- `component="nav"` must be a prop directly on `<Drawer ...>`, not on a
  `<Box component="nav">` wrapping it — grep for `<Box component="nav"` in
  `AppShell.tsx` and flag it as a fail (it breaks the permanent Drawer's
  full-height fill; see "Permanent nav must fill full page height" above).
  Also confirm the row `Box` holding the `Drawer` and main-content `Box`
  has `flexGrow: 1` in its `sx`, not just `display: 'flex'`.
