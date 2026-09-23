# Palette

Source of truth: `MyUABPortal/src/Containers/Portal/LightTheme.js` and
`DarkTheme.js`. All hex values below are copied directly from that
production theme, not re-derived or re-fetched.

## Trimmed core set — this is what `theme-templates/` wires into
`palette.primary`/`palette.secondary` and custom top-level palette keys for
every generated app:

| Token | Light hex | Dark hex | Notes |
|---|---|---|---|
| `primary.main` | `#1A5632` | `#1A5632` | UAB Green |
| `primary.light` | `#F4F4F4` | `#185843` | |
| `primary.dark` | `#033319` | `#033319` | = Dragon's Lair Green |
| `primary.contrastText` | `#fff` | `#fff` | |
| `secondary.main` | `#033319` | `#033319` | Dragon's Lair Green — identical both modes |
| `dragonGreen` (custom) | `#033319` | `#033319` | same value as `secondary.main`; kept as its own named token because the portal does, and because focus-ring / hover code reads it by this name, not by `secondary` |
| `campusGreen` (custom) | `#90D408` | `#90D408` | |
| `trustTeal` (custom) | `#68C6B8` | `#68C6B8` | |
| `coral` (custom) | `#ea6852` | `#ea6852` | used for snackbar/notification backgrounds in the portal |
| `error.main` | `#c7ba9b` | `#c7ba9b` | `light: #e3ddcd`, `dark: #aa9767`, both modes |
| `warning.main` | `#ffd400` | `#ffd400` | `light: #fff1ab`, `dark`/base `#ffe357`, both modes — portal's own `main` is actually `#ffe357`; see caveat below |
| `info.main` | `#80bc00` | `#80bc00` | |
| `success.main` | `#80BC00` | `#80BC00` | same value as `info.main` in the portal |
| `background.default` | `#F2F2F3` | `#022b1a` | |
| `background.paper` | `#ffffff` | `#1A5632` | paper == primary.main in dark mode |
| `divider` | `#033319` | `#558674` | portal uses `#D3D3D3` for `MuiDivider.root.borderColor` in light mode specifically — see `theme-templates/LightTheme.js` |
| `text.primary` | `#1A5632` | `#fff` | **Required, not optional.** See decision record below — omitting this is what caused the black-text bug. |

**Warning color caveat:** the portal's `warning` palette entry is
`{ main: '#ffe357', light: '#fff1ab', dark: '#ffd400' }` — i.e. its `main`
is the *lightest* of the three, which is unusual (normally `main` sits
between `light` and `dark`). This is copied faithfully in
`theme-templates/` rather than "corrected," since the portal is the
verified gold standard here — don't silently reorder it if you're editing
these templates later.

## Decision record (2026-09-23)

The user chose this trimmed set over wiring in the portal's full palette,
to keep generated demo apps' theme files simple and on-brand without
bloat they'll likely never use. The two names in the *previous* version of
this branding guidance — "Ever Loyal Evergreen" (`#17B045`) and "Bham Sky
Blue" (`#42CAF0`) — do **not** appear anywhere in the portal's actual
theme implementation (confirmed by direct read of `LightTheme.js`/
`DarkTheme.js`). They were presumably pulled from the public UAB brand
guide site directly rather than verified against a real, shipped
implementation. They are **not** carried forward into this skill's core
set or full-palette reference below — if they're still an active part of
the brand guide and should be reintroduced, that needs a fresh check
against `uab.edu/brandguide/university/colors`, not a guess.

## Decision record (2026-09-23, `text.primary`)

Found via a user report on `uab-app-creator-nobrand-helloworld`: the
generated app's light-mode homepage rendered "Welcome!" and other default
`<Typography>` text in near-black instead of UAB Green.

Root cause: the portal's `LightTheme.js`/`DarkTheme.js` hardcode `color:
'#1A5632'`/`'#fff'` on every individual typography variant (h1-h6, body1,
body2, button, caption, overline, subtitle1) — MUI v4-era
belt-and-suspenders styling. When `theme-templates/` translated this to v5
idiom, `themeShared.js`'s `typographyVariants` correctly dropped the
per-variant repetition (v5 `Typography` should inherit color from
`palette.text.primary`) — but nothing ever set `palette.text.primary` to
compensate. It was previously listed only under "full portal palette,
documented but not wired" below, which undersold how load-bearing it is.

Effect: with `text.primary` unset, MUI silently falls back to its own
built-in default (`rgba(0, 0, 0, 0.87)` in light mode, `#fff` in dark
mode) instead of raising an error. Dark mode looked correct by pure
coincidence — MUI's own dark-mode default happens to equal the portal's
branded dark text color. Light mode did not, because MUI's default there
is black, not UAB Green. **A theme review that only checks dark mode, or
only checks that *some* color renders, will miss this class of bug** —
always verify text color in light mode specifically, and verify it's
coming from an explicit token, not an unset-property coincidence.

Fix: `text.primary` is promoted from "documented, not wired" to the
trimmed core set (row above) and is now set explicitly in both
`theme-templates/LightTheme.js` and `DarkTheme.js`, with a comment
explaining why it can't be left to MUI's default even where the default
happens to match.

`text.secondary` is deliberately **not** promoted the same way — the
portal's own `text.secondary` values are `'#fff'` (light) / `'#1A5632'`
(dark), which look like they're meant for text sitting on a colored
(green) surface, not as a drop-in replacement for MUI's `text.secondary`
(used broadly for helper text, captions, and secondary list text on plain
`background.paper`). Wiring `text.secondary: '#fff'` into the light theme
verbatim would make things like `<Typography color="text.secondary">`
invisible against a white `Paper` — trading one contrast bug for a worse
one. If a generated app needs the portal's actual `text.secondary`
behavior, that requires reading how the portal *uses* that token in
context first, not copying the raw value.

## Full portal palette — documented, NOT wired into generated themes

For audit mode to recognize when an existing (non-generated) app already
uses one of these, and as a reference if a generated app's needs outgrow
the trimmed set above:

```
green: { dark: '#1A5632', light: '#4B8975' }
black: { default: '#000000' }
white: { default: '#fff' }
campusGreen: { default: '#90D408', highlight20: '#D7EFA6', highlight10: '#EAF7D0', highlight5: '#F4FBE7' }
trustTeal: { default: '#68C6B8', highlight30: '#C0E4DA', highlight20: '#CFEAE2', highlight10: '#E2F2EC' }
neutral: { neutral20: '#D1D3D4', neutral10: '#E6E7E8', neutral5: '#F1F2F2' }
text: { default: '#1A5632' (light) / '#fff' (dark), secondary: '#fff' (light) / '#1A5632' (dark) }
accent: { primary: '#ECECED' (light) / '#033319' (dark) }
certifiedgold: { main: '#FDB913' }
gold: { main: '#a59466' }
silver: { main: '#b1b1b1' }
bronze: { main: '#c67d30' }
```

`certifiedgold`/`gold`/`silver`/`bronze` are award/recognition-tier colors
(used for things like certification badges) — almost never relevant to a
generic generated app; include them only if the app leader specifically
describes an awards/recognition/leaderboard feature.

## Never hardcode a brand hex in a component

Any `sx`/style prop using a UAB color must reference `theme.palette.*`,
never a literal hex string. If a needed color has no token yet, add it to
`theme-templates/LightTheme.js`/`DarkTheme.js` first — don't reach for a
raw hex as a shortcut. (This is precisely the gap found in the
`timeoff-demo-app-slim-litelllm` audit: `Footer.tsx` hardcoded
`backgroundColor: '#033319'` instead of `theme.palette.dragonGreen`,
because no such token existed at the time.)
