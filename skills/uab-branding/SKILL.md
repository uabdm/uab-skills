---
name: uab-branding
description: UAB brand theme (colors, typography, logo, footer) and WCAG 2.1 AA accessibility patterns (focus rings, skip links, landmarks, ARIA, forms, color/status indicators) for UAB web apps — sourced from MyUABPortal, UAB's real production portal. Two modes, GENERATE and AUDIT (see below). GENERATE is invoked only by another skill's own instructions calling this one by name mid-scaffold — never invoke it standalone to "start" an app from scratch. AUDIT is invoked directly, any time you're asked to check, review, or verify an existing UAB (or UAB-adjacent) app's branding, theme, colors, fonts, logo, footer, or accessibility/WCAG 2.1 AA compliance — including "does this app follow our brand guidelines," "is this accessible," or "audit this app against our standards."
---

# UAB Branding + Accessibility

Single source of truth for what "UAB brand + WCAG 2.1 AA compliant" actually
means in code, extracted and verified against
`C:\Users\still\Documents\GitHub\MyUABPortal` — UAB's real production
portal — rather than re-derived from prose or re-fetched from the public
brand guide site on every run. Where the portal's own implementation is
legacy (Vite/CRA, MUI v5 with the v4 `adaptV4Theme`/`overrides` shim), every
pattern here has already been translated to modern MUI
(`components.styleOverrides`) syntax and Next.js App Router conventions —
copy these templates directly, don't re-derive from the portal's raw
syntax.

**Why this exists as its own skill, not prose inside an app-generator:**
prose instructions ("populate the palette," "add focus rings") get skipped
under time pressure; literal code that an agent copies verbatim doesn't.
Bundling this as a standalone skill also means it can be pointed at an
*existing* app to check compliance, not just invoked while generating a new
one.

## Mode detection

- Invoked with `generate` arguments (see below) → **generate mode**.
- Invoked directly against an existing app's source tree, with no
  `generate` arguments → **audit mode**.

## Generate mode

Called with: `generate --framework=nextjs-app-router --app-name=<name>
--theme-dir=<path, default src/theme> --layout-dir=<path, default
src/components/layout>`. (Only `nextjs-app-router` is supported today —
there is no branding/WCAG surface for a headless Python worker, since it
has no UI.)

Produce, using the literal templates in `references/`:

1. `<theme-dir>/LightTheme.js`, `<theme-dir>/DarkTheme.js`, and
   `<theme-dir>/themeShared.js` — from `references/theme-templates/`
   verbatim, substituting nothing (they take no per-app parameters; the
   palette/typography/focus/motion rules are fixed brand facts, not
   per-app choices).
2. `<layout-dir>/Footer.tsx` — from `references/footer-template.md`
   verbatim, including the exact Nondiscrimination Statement dialog text.
3. Logo asset: copy `assets/uabCoreLogoWhiteSmall.png` to the calling
   skill's `public/uab-logo-white.png`, and wire it into the AppBar exactly
   as described in `references/logo-usage.md`.
4. Landmark + skip-link structure: apply `references/landmarks-and-structure.md`'s
   patterns to whatever `AppShell.tsx`/`layout.tsx` the calling skill is
   assembling — `component="header"` on the AppBar, the skip link as the
   very first rendered element, `component="main"` + `id="main-content"` +
   `tabIndex={-1}` on the content region, `component="nav"` + `aria-label`
   on the nav, `component="footer"` on Footer (already true of the Footer
   template from step 2).
5. Typekit `<link>`: insert the literal tag from `references/typography.md`
   into the root `app/layout.tsx`'s `<head>`.
6. Page-stub heading rule: any generated page title uses
   `variant`/`component` decoupling per `references/landmarks-and-structure.md`
   — exactly one real `<h1>` per page.
7. ARIA/forms/color-status rules (`references/aria-patterns.md`,
   `references/forms.md`, `references/color-and-status.md`) apply to
   whatever interactive elements, forms, or status indicators the calling
   skill generates elsewhere — hand these files to that generation step as
   the accessibility ground rules, don't just apply them to the four files
   above.

**Never soften or summarize a rule from these reference files when
generating** — copy the literal snippet. If a generated component doesn't
need a rule (e.g. no forms in a static page), skip that reference file
entirely rather than paraphrasing it.

## Audit mode

Given a path to an existing app's source tree: walk
`references/audit-checklist.md` top to bottom. For each item, read/grep the
relevant files and report **pass**, **fail**, or **not applicable** with a
file:line citation for both passes and fails (a pass needs a citation too —
"trust but verify" — since the point is confirming the rule is actually
implemented, not just plausible). End with a short summary grouped by
"got it right" / "fell short," same shape as a normal code-review report.
Do not modify the audited app — audit mode is read-only unless the caller
explicitly asks for the findings to be fixed, in which case treat that as a
separate, explicit follow-up request, not implied by "audit."

## Reference index

- `references/palette.md` — trimmed core palette (what generate mode wires
  in) plus the portal's full palette, documented as available-but-not-wired
- `references/typography.md` — font-per-variant mapping, the real Typekit
  `<link>`, Next.js placement
- `references/theme-templates/` — `LightTheme.js`, `DarkTheme.js`,
  `themeShared.js` (literal, generate mode copies these verbatim)
- `references/focus-and-motion.md` — the focus-ring rule as prose+rationale
  (the literal code lives in the theme templates)
- `references/landmarks-and-structure.md` — landmarks, skip link, heading
  hierarchy
- `references/aria-patterns.md` — icon-button/menu/live-region/pagination/
  tab-panel ARIA snippets
- `references/forms.md` — label/required/aria-invalid + the
  helperText/aria-describedby pattern
- `references/color-and-status.md` — never-color-alone rule,
  aria-label-not-just-tooltip rule
- `references/footer-template.md` — literal `Footer.tsx`, verbatim
  Nondiscrimination text
- `references/logo-usage.md` — logo sizing/placement/alt-text rules
- `references/audit-checklist.md` — every rule above as a pass/fail item
