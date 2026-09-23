# Focus ring + reduced motion — rationale

The literal code lives in `theme-templates/themeShared.js`
(`focusRingComponents`, `reducedMotionCssBaseline`) — this file is the
"why," for anyone extending or auditing against it.

## Focus ring (WCAG 2.1 AA, SC 2.4.7 Focus Visible)

Source of truth: `MyUABPortal/src/Containers/Portal/LightTheme.js:360-366,
438-444, 569-576` (and the matching block in `DarkTheme.js`).

**Never suppress the default outline** (`outline: 'none'` or
`outline: 0` anywhere is a hard fail in audit mode unless immediately
paired with a replacement outline on the same selector). Instead, restyle
it per component type:

- `MuiButtonBase` (covers every button, icon button, list item button,
  tab, menu item — anything clickable built on MUI's base) —
  `&.Mui-focusVisible { outline: 3px solid <color>; outline-offset: 2px; }`
- `MuiInputBase` (text fields, selects) —
  `&:focus-within { outline: 3px solid <color>; outline-offset: 1px; }`
  — a tighter 1px offset than buttons, so the ring doesn't crowd an
  adjacent floating label.
- `MuiLink` — `&:focus-visible { outline: 3px solid <color>; outline-offset: 2px; }`

Color: `#033319` (Dragon's Lair Green) in light mode, `#fff` in dark mode —
chosen for contrast against each mode's typical background, matching the
portal exactly.

**Why per-component, not one global `*:focus-visible` rule:** a single
global rule can't give inputs a different offset than buttons, and doesn't
compose cleanly with components (like `MuiLink`) that need
`:focus-visible` rather than MUI's `Mui-focusVisible` class. If you're
tempted to simplify to one global rule, don't — this is the portal's
actual, tested pattern, not a simplification target.

## Reduced motion (WCAG 2.1 AA, SC 2.3.3 Animation from Interactions)

Source: `MyUABPortal/src/Containers/Portal/LightTheme.js:217-224` (verbatim
identical in `DarkTheme.js:224-231` — the one place this skill's version
improves on the portal is deduplicating that copy-paste into
`themeShared.js`'s single `reducedMotionCssBaseline` export).

Applies to `*, *::before, *::after` — not scoped to `body` alone. A
`body`-only version (which a since-superseded version of this branding
guidance produced) only disables animation on the `body` element itself,
not its descendants, and is effectively a no-op for almost every real
animated element in an app.

## Audit-mode check

- Grep the theme files for `outline` — confirm all three selectors above
  are present, with the correct color per mode.
- Grep for `outline: none` / `outline: 0` / `outline: 'none'` anywhere in
  the codebase (not just theme files — a component-level `sx` override can
  reintroduce this) with no adjacent replacement outline — flag as a fail.
- Grep for `prefers-reduced-motion` — confirm it's present and targets
  `*, *::before, *::after` (or an equivalently broad selector), not just
  `body`.
