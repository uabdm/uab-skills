# UAB Branding — fetch and generate

Do this before generating any theme or layout files. Fetch these four UAB
brand guide URLs and use the data read from them to generate the theme files
— do not guess or invent brand values:

- Colors: https://www.uab.edu/brandguide/university/colors
- Color Accessibility: https://www.uab.edu/brandguide/university/colors/color-accessibility
- Fonts: https://www.uab.edu/brandguide/university/fonts
- Logo: https://www.uab.edu/brandguide/university/core-university-logo

From COLORS, extract all primary and secondary color hex values and names —
populate the MUI palette in both `LightTheme.js` and `DarkTheme.js`.

From COLOR ACCESSIBILITY, extract any documented approved
foreground/background pairings and any combinations flagged as failing
contrast — use this to choose text/icon colors anywhere a brand color is a
background (AppBar, buttons, badges, alerts) — prefer the documented pairing
over guessing a contrast-safe color.

From FONTS, extract the primary sans-serif font (body/UI), the alternate
serif/slab font (headings), and the Microsoft Office fallback fonts for each.
Note these are Adobe Creative Cloud fonts requiring the org's Adobe
subscription — add this as a comment in the theme files.

From LOGO, extract the clear space rules and minimum sizes (for any logo
placement other than the top nav bar, which uses a fixed asset — see LOGO
ASSET below). Note that actual logo files are behind a login at the Digital
Asset Library (https://digitalassets.uab.edu) — include a TODO placeholder
anywhere else the app displays a logo (e.g. AuthGate's sign-in splash).

## Logo asset (top navigation bar only) — bundled with this skill

The top navigation bar (see AppShell in `scaffold-web-nextjs.md`) always uses
one fixed, known logo file — the UAB Core Logo, white version — not
something fetched or guessed.

This skill bundles that file at `assets/uabCoreLogoWhiteSmall.png`. Copy it
— do not move or delete the original — to `public/uab-logo-white.png` in the
generated project. Reference `/uab-logo-white.png` from `AppShell.tsx`.

(This is a deliberate improvement over the raw IDEA.md flow, which has the
project leader download this file separately and place it beside the
document before generation. Running inside a skill means the asset already
travels with the tooling, so that manual step is unnecessary here.)

## `src/theme/LightTheme.js`

MUI `createTheme()` with UAB colors in light mode (current MUI major — the
snippets in this skill are written against MUI v7; if the current major at
generation time is newer, re-verify the AppShell/theme snippets against it
before writing them out). Primary: UAB Green `#1A5632`, background default:
`#F2F2F3`, paper: `#fff`.

Include the full brand palette as a comment block at the top:

```js
/*
 * UAB OFFICIAL BRAND PALETTE
 * Generated from: https://www.uab.edu/brandguide/university/colors
 *
 * PRIMARY
 *   UAB Green            #1A5632   Pantone 357
 *   UAB Gold             #FDB913   Pantone 7549
 *
 * SECONDARY ACCENTS
 *   Dragon's Lair Green  #033319   Pantone 5535
 *   Campus Green         #90D408   Pantone 376
 *   Ever Loyal Evergreen #17B045   Pantone 2257
 *   Bham Sky Blue        #42CAF0   Pantone 2198
 *
 * Full brand guide:  https://www.uab.edu/brandguide/university/colors
 * Fonts:             https://www.uab.edu/brandguide/university/fonts
 * Logo assets:       https://digitalassets.uab.edu (requires UAB login)
 * Accessibility:     WCAG 2.1 AA
 *
 * FONTS (Adobe Creative Cloud — requires UAB Adobe subscription)
 *   Primary (body/UI): [primary font from brand guide], fallback: Arial / Aptos
 *   Heading:           [heading font from brand guide], fallback: Rockwell
 */
```

## `src/theme/DarkTheme.js`

Same palette, dark mode backgrounds: default `#022b1a`, paper `#1A5632`. Same
comment block at the top.

## WCAG 2.1 AA requirements (both themes)

- Focus rings on all interactive elements: 3px solid, 2px offset. Light
  mode: outline color `#033319`. Dark mode: outline color `#fff`.
- `prefers-reduced-motion`: disable animations globally via `MuiCssBaseline`.
- `textTransform: 'none'` on all buttons.
