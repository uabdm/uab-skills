# Typography

Source of truth: `MyUABPortal/src/Containers/Portal/LightTheme.js` /
`DarkTheme.js` `typography` block, and the Typekit `<link>` in the
portal's `index.html`. Both fonts are Adobe Fonts (Typekit) — Kulturista
and Proxima Nova — requiring the org's Adobe subscription, already
provisioned under kit ID `ygy8wyj`.

## Font-per-variant mapping (identical in both themes)

| Variant | Font | Fallback |
|---|---|---|
| `h1` | `'kulturista-web'` | `sans-serif` |
| `h3` | `'kulturista-web'` | `sans-serif` |
| `h2`, `h4`, `h5`, `h6`, `subtitle1`, `body1`, `body2`, `button`, `caption`, `overline` | `'proxima-nova'` | `'Helvetica', 'Arial', sans-serif` |

Only `h1` and `h3` use Kulturista — it's a display face used sparingly for
the two biggest headings. Everything else, including button text, uses
Proxima Nova. This is more specific than "one heading font, one body
font" — don't collapse it back to that.

Base sizing: `fontSize: 16`, `htmlFontSize: 16`,
`fontWeightLight/Regular/Medium/Bold: 300/400/500/700`. Wrap the theme in
MUI's `responsiveFontSizes()` (the portal does this in its top-level
`getTheme()`) so heading sizes scale down on small viewports — apply this
in whichever file constructs the final theme object handed to
`ThemeProvider` (see `theme-templates/themeShared.js`).

## Font loading — the real, working Typekit link

The org already has a Typekit kit provisioned and serving both fonts. Use
the literal tag, not a placeholder:

```html
<link rel="stylesheet" media="all" href="https://use.typekit.net/ygy8wyj.css" type="text/css">
```

**Next.js App Router placement:** the portal is a Vite SPA with a raw
`index.html`, so it just drops this in `<head>` directly — there is no
`index.html` entry point in a Next.js App Router app. Instead, insert this
`<link>` inside the JSX returned by the root `app/layout.tsx`'s `<head>`
region (Next.js App Router renders an explicit `<head>` you can add tags
to directly inside `<html>`, before `<body>`):

```tsx
export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <head>
        <link rel="stylesheet" media="all" href="https://use.typekit.net/ygy8wyj.css" type="text/css" />
      </head>
      <body>
        {/* ... */}
      </body>
    </html>
  );
}
```

This replaces the old "TODO: add your Typekit embed" placeholder comment
entirely — the kit is real and already serving these two font families for
the org, so a fresh generated app doesn't need a manual step to get
correctly-branded text.

**One caveat to verify, not assume:** Adobe Fonts (Typekit) kits are
typically domain-restricted in the Adobe account's kit settings. This kit
(`ygy8wyj`) is confirmed working for the portal's own domain(s). Before
relying on it for a newly deployed app on a different domain, confirm that
domain is on the kit's allowed-domains list in Adobe's dashboard — flag
this in generated output (e.g. a short README note), don't silently assume
it "just works" everywhere. Local development (`localhost`) is typically
allowed by default on most Typekit kits, so this is a deploy-time
consideration, not a local-dev blocker.

## What NOT to do

- Don't hardcode `fontFamily` strings inline on individual `Typography`
  components — the theme's `typography.<variant>.fontFamily` already
  covers every case above.
- Don't set a global `body { font-family: ... }` in a stylesheet as a
  substitute for the theme's typography block — MUI reads font family per
  variant from the theme object, and a global CSS override can silently
  diverge from it.
