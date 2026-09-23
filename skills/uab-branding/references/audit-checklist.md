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

## WCAG — focus & motion ([`focus-and-motion.md`](focus-and-motion.md))

6. Focus-ring overrides exist for `MuiButtonBase` (`.Mui-focusVisible`),
   `MuiInputBase` (`:focus-within`), and `MuiLink` (`:focus-visible`), each
   a solid outline (not just a color/box-shadow change) with an offset.
7. No `outline: none`/`outline: 0` anywhere without an immediately
   adjacent replacement outline on the same selector.
8. `prefers-reduced-motion: reduce` is handled globally (`*, *::before,
   *::after` or equivalently broad), not scoped to a single element.

## WCAG — structure ([`landmarks-and-structure.md`](landmarks-and-structure.md))

9. Header uses `component="header"`; main content uses `component="main"`
   with `id="main-content"` and `tabIndex={-1}`; nav uses `component="nav"`
   with an `aria-label`; footer uses `component="footer"`.
10. A skip-to-content link (`href="#main-content"`) is the first rendered
    element in the app shell, visually hidden until keyboard-focused.
11. Every page has exactly one `component="h1"` — check the top-level
    `Typography` on each route; flag zero or more than one.

## WCAG — ARIA / interaction ([`aria-patterns.md`](aria-patterns.md), [`color-and-status.md`](color-and-status.md))

12. Every icon-only `IconButton`/similar control has `aria-label` directly
    on the control (not only inside a `Tooltip`), and its icon (if
    decorative) has `aria-hidden="true"`.
13. Menu-trigger controls carry `aria-controls`/`aria-haspopup`/`aria-expanded`.
14. Async loading/error states use `role="status"`/`role="alert"`
    appropriately, not silent or purely-visual state changes.
15. Any status/state conveyed by color also carries a distinct icon shape
    and/or visible text — no color-only indicators.

## WCAG — forms ([`forms.md`](forms.md))

16. Every text/select field has a real `label` (not a placeholder standing
    in for one).
17. Every `Checkbox`/`Radio` is wrapped in `FormControlLabel` for its
    accessible name, not given a non-functional `label` prop directly on
    the control.
18. Fields with validation use `error` + `helperText` + a matching
    `aria-describedby`, not a bare red border with no text explanation.

## Branding — logo, footer, fonts

19. Top nav logo: a plain `<img>` (never `next/image`), `height: 'auto'`,
    descriptive `alt` text, no dark-mode swap — [`logo-usage.md`](logo-usage.md).
20. Footer link set matches exactly (or, for an app that predates this
    skill, is at least internally consistent and not missing the
    Nondiscrimination Statement) — [`footer-template.md`](footer-template.md).
21. Nondiscrimination Statement dialog text matches verbatim, not
    paraphrased or shortened.
22. Typography: headings use the display face (h1/h3), body/UI text uses
    the body face with a real fallback stack, per
    [`typography.md`](typography.md) — check the theme's `typography`
    block, not just that *some* custom font is referenced somewhere.

## Reporting

For each numbered item, one line: pass/fail/n/a, file:line, one-sentence
reason if it's a fail. Close with a short prose summary grouping "got it
right" vs. "fell short," same shape used for the
`timeoff-demo-app-slim-litelllm` audit this checklist was built from —
don't just dump the 22-line checklist and stop, synthesize it.
