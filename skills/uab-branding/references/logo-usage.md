# Logo usage

## Top navigation bar (the only placement this skill wires automatically)

Single fixed asset — `assets/uabCoreLogoWhiteSmall.png` — the UAB Core
Logo, white version, matching `MyUABPortal`'s desktop/tablet logo asset
(`src/Containers/Portal/Top/TopLogo/uabCoreLogoWhiteSmall.png`, the same
file). Copy it to the generated app's `public/uab-logo-white.png`.

**Deliberately a single asset, no responsive swap:** the portal itself
also renders a second, monogram-only logo below its `sm` breakpoint (for a
compact mobile header). This skill does not adopt that second asset or the
responsive swap logic — the single core logo is used at every viewport
width, matching the existing app-creator skill's approach. If a future app
needs the monogram treatment, source
`MyUABPortal/src/Containers/Portal/Top/TopLogo/uabMonogramWhiteSmall.png`
directly rather than guessing at a substitute.

```tsx
<img
  src="/uab-logo-white.png"
  alt="UAB logo"
  style={{ maxWidth: 270, height: 'auto', display: 'block' }}
/>
```

Rules, non-negotiable:

- Use a plain `<img>`, never `next/image` — its required `width`/`height`
  props are easy to set to a ratio that doesn't match the real file,
  which stretches or squishes the logo.
- Never set a fixed `height` alongside `maxWidth`/`width` — `height` must
  stay `'auto'`, or the browser stretches the image to fill both
  constraints.
- Never swap in a different logo variant for dark mode — the AppBar
  background stays UAB Green in both modes (see `scaffold`'s AppShell
  spec), so the white logo variant is correct in both.
- Position top-left of the AppBar `Toolbar`, before the app name text.
- Alt text: exactly `"UAB logo"` — descriptive, not a filename, matching
  the portal's own convention.

## Any other logo placement (e.g. an `AuthGate` sign-in splash)

The actual logo files live behind a login at UAB's Digital Asset Library
(`https://digitalassets.uab.edu`) — this skill only bundles the one top-nav
asset above. For any other placement, leave a clear `TODO` comment
pointing at the Digital Asset Library rather than reusing or resizing the
top-nav asset out of context, and note the general clear-space rule: keep
at least the logo's own cap-height of empty space on all sides before any
other element, text, or edge — don't crowd it.

## Audit-mode check

- Confirm the top nav uses `/uab-logo-white.png` (or an equivalent bundled
  UAB core logo asset), via a plain `<img>` (not `next/image`), with
  `height: 'auto'` and no separate fixed `height`.
- Confirm alt text is present and descriptive (not empty, not a filename).
- Confirm no dark-mode-specific logo swap exists on the AppBar.
