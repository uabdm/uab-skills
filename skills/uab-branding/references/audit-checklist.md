# Audit checklist

Walked top to bottom in audit mode (see `SKILL.md`). For each item: read or
grep the relevant file(s) and report **pass** / **fail** / **n/a**, with a
file:line citation either way. Group the final report the same way a normal
code review would — what it got right, then what it fell short on — most
important gaps first.

## Palette & theme

1. `palette.primary.main` is UAB Green `#1A5632` — [`palette.md`](palette.md).
2. `palette.secondary.main` (or an equivalent named token) is Dragon's
   Lair Green `#033319`.
3. Light `background.default`/`background.paper` are `#F2F2F3`/`#fff`;
   dark are `#022b1a`/`#1A5632`.
4. At least the accent colors actually *used* by the app (buttons, badges,
   status indicators, etc.) exist as real `theme.palette.*` tokens —
   **not** hardcoded hex strings in component `sx`/style props. Grep for
   raw hex literals (`#[0-9a-fA-F]{3,6}`) outside the theme files
   themselves — flag every hit as a fail, one per file:line.
5. `MuiButton`/`MuiTab`/`MuiFab` have `textTransform: 'none'`.
6. `palette.text.primary` is explicitly set — `#1A5632` in the light
   theme, `#fff` in the dark theme — not left unset to fall through to
   MUI's own default. Check by rendering (or reading) a plain
   `<Typography>` with no `color` prop in **light mode specifically**: if
   it's near-black (`rgba(0,0,0,0.87)`) rather than UAB Green, that's a
   fail even though the same check in dark mode would coincidentally
   pass — see the `text.primary` decision record in
   [`palette.md`](palette.md).
7. No `Typography`/text element styled `color: 'primary.main'`,
   `color="primary"`, `color: 'secondary.main'`, or `dragonGreen.main`
   sits inside a `Paper`, `Card`, `Dialog`, or anything else resolving to
   `background.paper`. In dark mode `background.paper` **equals**
   `primary.main` (`#1A5632`) — text colored that way is ~1:1 contrast
   against it, effectively invisible (confirmed bug — see the
   `primary.main` decision record in [`palette.md`](palette.md)). Check
   **dark mode specifically**; light mode's white `background.paper` hides
   this completely. Grep for `color:\s*['"]primary` and `color="primary"`
   and check each hit's surrounding container. The fix is to remove the
   override and let the text inherit `text.primary` (already correctly
   branded per mode), not to swap in a different hardcoded color.

## WCAG — focus & motion ([`focus-and-motion.md`](focus-and-motion.md))

8. Focus-ring overrides exist for `MuiButtonBase` (`.Mui-focusVisible`),
   `MuiInputBase` (`:focus-within`), and `MuiLink` (`:focus-visible`), each
   a solid outline (not just a color/box-shadow change) with an offset.
9. No `outline: none`/`outline: 0` anywhere without an immediately
   adjacent replacement outline on the same selector.
10. `prefers-reduced-motion: reduce` is handled globally (`*, *::before,
    *::after` or equivalently broad), not scoped to a single element.

## WCAG — structure ([`landmarks-and-structure.md`](landmarks-and-structure.md))

11. Header uses `component="header"`; main content uses `component="main"`
    with `id="main-content"` and `tabIndex={-1}`; nav uses `component="nav"`
    with an `aria-label`, passed **directly as props on `<Drawer>`** (not
    on a wrapping `<Box component="nav">` — see item 12); footer uses
    `component="footer"`.
12. A permanent desktop nav `Drawer` fills the full page height, no matter
    how few nav items exist or how short the page content is — its
    `background.paper` fill shouldn't stop partway down and expose
    `background.default` underneath. Fail if: (a) `<Box component="nav">`
    wraps the `Drawer` instead of `component="nav"` being a prop on the
    `Drawer` itself, or (b) the flex row holding the `Drawer` and the
    main-content `Box` has `display: 'flex'` without also `flexGrow: 1`.
    Both break the height-stretch chain — see "Permanent nav must fill
    full page height" in
    [`landmarks-and-structure.md`](landmarks-and-structure.md) for the
    exact mechanism.
13. A skip-to-content link (`href="#main-content"`) is the first rendered
    element in the app shell, visually hidden until keyboard-focused.
14. Every page has exactly one `component="h1"` — check the top-level
    `Typography` on each route; flag zero or more than one.

## WCAG — ARIA / interaction ([`aria-patterns.md`](aria-patterns.md), [`color-and-status.md`](color-and-status.md))

15. Every icon-only `IconButton`/similar control has `aria-label` directly
    on the control (not only inside a `Tooltip`), and its icon (if
    decorative) has `aria-hidden="true"`.
16. Menu-trigger controls carry `aria-controls`/`aria-haspopup`/`aria-expanded`.
17. Async loading/error states use `role="status"`/`role="alert"`
    appropriately, not silent or purely-visual state changes.
18. Any status/state conveyed by color also carries a distinct icon shape
    and/or visible text — no color-only indicators.

## WCAG — forms ([`forms.md`](forms.md))

19. Every text/select field has a real `label` (not a placeholder standing
    in for one).
20. Every `Checkbox`/`Radio` is wrapped in `FormControlLabel` for its
    accessible name, not given a non-functional `label` prop directly on
    the control.
21. Fields with validation use `error` + `helperText` + a matching
    `aria-describedby`, not a bare red border with no text explanation.

## Branding — logo, footer, fonts

22. Top nav logo: a plain `<img>` (never `next/image`), `height: 'auto'`,
    descriptive `alt` text, no dark-mode swap — [`logo-usage.md`](logo-usage.md).
23. Footer link set matches exactly (or, for an app that predates this
    skill, is at least internally consistent and not missing the
    Nondiscrimination Statement) — [`footer-template.md`](footer-template.md).
24. Nondiscrimination Statement dialog text matches verbatim, not
    paraphrased or shortened.
25. The `Typography` inside `DialogTitle` does NOT have `component="h2"`
    — `DialogTitle` already renders `<h2>` internally, so a nested one is
    invalid HTML and throws a hydration error the moment the dialog opens
    (confirmed bug — see [`footer-template.md`](footer-template.md)). Grep
    for `<DialogTitle` in the app and check every `Typography` inside it.
26. Typography: headings use the display face (h1/h3), body/UI text uses
    the body face with a real fallback stack, per
    [`typography.md`](typography.md) — check the theme's `typography`
    block, not just that *some* custom font is referenced somewhere.
27. Typography sizing: every variant in the theme's `typography` block has
    an explicit `fontSize` matching [`typography.md`](typography.md)'s
    table — not just `fontFamily`/`fontWeight`. Fail if `h1`'s computed
    size is anywhere near MUI's raw default (`6rem`/96px) instead of the
    branded `2.1rem`; that specific symptom (a several-line-tall heading)
    means `responsiveFontSizes()` is scaling an unset, MUI-default base
    size rather than the portal's actual one. Also flag any page-level
    `Typography` using `variant="h1"` — per
    [`landmarks-and-structure.md`](landmarks-and-structure.md)'s heading
    hierarchy rule, the page title should decouple `variant` (visual size,
    usually `h4`-ish) from `component="h1"` (semantic level), not use the
    literal `h1` variant.

## Reporting

For each numbered item, one line: pass/fail/n/a, file:line, one-sentence
reason if it's a fail. Close with a short prose summary grouping "got it
right" vs. "fell short," same shape used for the
`timeoff-demo-app-slim-litelllm` audit this checklist was built from —
don't just dump the 27-line checklist and stop, synthesize it.
