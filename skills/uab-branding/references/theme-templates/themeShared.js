// Shared UAB theme fragments used by both LightTheme.js and DarkTheme.js —
// kept in one place so the WCAG rules below exist exactly once instead of
// being copy-pasted per theme (the portal itself duplicates them; this
// skill doesn't have to). Source of truth for every value here:
// MyUABPortal's LightTheme.js/DarkTheme.js, translated from MUI v4
// `overrides`/`adaptV4Theme` syntax to modern `components.styleOverrides`.

// WCAG 2.1 AA focus-ring rule: NEVER suppress the default focus outline.
// Instead restyle it, per component type, via the matching focus-visible
// pseudo-selector, with a solid 3px outline and 1-2px offset. This is
// deliberately three targeted overrides, not one global `*:focus` rule —
// that's what the portal actually does, and it's more precise (inputs get
// a tighter 1px offset than buttons/links, so the outline doesn't crowd
// adjacent form labels).
//
// outlineColor: '#033319' (Dragon's Lair Green) in light mode, '#fff' in
// dark mode — passed in by LightTheme.js / DarkTheme.js.
export function focusRingComponents(outlineColor) {
  return {
    MuiButtonBase: {
      styleOverrides: {
        root: {
          '&.Mui-focusVisible': {
            outline: `3px solid ${outlineColor}`,
            outlineOffset: '2px',
          },
        },
      },
    },
    MuiInputBase: {
      styleOverrides: {
        root: {
          '&:focus-within': {
            outline: `3px solid ${outlineColor}`,
            outlineOffset: '1px',
          },
        },
      },
    },
    MuiLink: {
      styleOverrides: {
        root: {
          textDecoration: 'none',
          '&:focus-visible': {
            outline: `3px solid ${outlineColor}`,
            outlineOffset: '2px',
          },
        },
      },
    },
  };
}

// `textTransform: 'none'` everywhere MUI defaults to uppercasing text —
// buttons, tabs, and extended FABs.
export const noTextTransformComponents = {
  MuiButton: { styleOverrides: { root: { textTransform: 'none' } } },
  MuiTab: { styleOverrides: { root: { textTransform: 'none' } } },
  MuiFab: { styleOverrides: { extended: { textTransform: 'none' } } },
};

// prefers-reduced-motion: applied to `*, *::before, *::after` globally via
// MuiCssBaseline, not scoped to `body` alone — a `body`-only rule (as an
// earlier, weaker version of this skill's guidance produced) only disables
// animation on the body element itself, not its descendants.
export const reducedMotionCssBaseline = {
  MuiCssBaseline: {
    styleOverrides: {
      '@media (prefers-reduced-motion: reduce)': {
        '*, *::before, *::after': {
          animationDuration: '0.01ms !important',
          animationIterationCount: '1 !important',
          transitionDuration: '0.01ms !important',
          scrollBehavior: 'auto !important',
        },
      },
    },
  },
};

// Font-per-typography-variant map — see ../typography.md for the full
// rationale. Only h1/h3 use the display face; everything else, including
// button text, uses the body face.
export const fontHeading = "'kulturista-web', sans-serif";
export const fontBody = "'proxima-nova', 'Helvetica', 'Arial', sans-serif";

// fontSize/lineHeight/letterSpacing below are copied verbatim from the
// portal's typography block (identical in LightTheme.js and DarkTheme.js —
// only color differs between the two, and color is handled via
// palette.text.primary now, not per-variant here). This is NOT optional
// decoration: every one of these variants is wrapped in MUI's
// `responsiveFontSizes()` by LightTheme.js/DarkTheme.js (matching the
// portal's own theme.js -> getTheme()), and responsiveFontSizes() scales
// UP from whatever base fontSize a variant has. Leave fontSize unset here
// and MUI substitutes its own raw defaults (h1: 6rem, h2: 3.75rem, h3:
// 3rem, ...) as the base — responsiveFontSizes then scales that already
// oversized default even larger at wide breakpoints. Confirmed bug: a
// generated page using `variant="h1"` rendered a ~150px, 3-line-wrapping
// heading in uab-app-creator-nobrand-hello-world-brand-uabgreen because
// this block only had fontFamily/fontWeight. A page using a smaller
// variant (e.g. h4) won't look broken, but it's still silently running on
// MUI's un-branded size scale rather than the portal's — same "coincidence
// masks the gap" trap as the missing text.primary bug.
export const typographyVariants = {
  fontSize: 16,
  htmlFontSize: 16,
  fontWeightLight: 300,
  fontWeightRegular: 400,
  fontWeightMedium: 500,
  fontWeightBold: 700,
  h1: { fontFamily: fontHeading, fontWeight: 600, fontSize: '2.1rem', lineHeight: 1.3, letterSpacing: '0em' },
  h2: { fontFamily: fontBody, fontWeight: 500, fontSize: '1.9rem', lineHeight: 1.3, letterSpacing: '0em' },
  h3: { fontFamily: fontHeading, fontWeight: 600, fontSize: '1.4rem', lineHeight: 1.3 },
  h4: { fontFamily: fontBody, fontWeight: 600, fontSize: '1.2rem', lineHeight: 1.1, letterSpacing: '0em' },
  h5: { fontFamily: fontBody, fontWeight: 500, fontSize: '1.05rem', lineHeight: 1.2 },
  h6: { fontFamily: fontBody, fontWeight: 600, fontSize: '0.89rem', lineHeight: 1.3, letterSpacing: '0em' },
  subtitle1: { fontFamily: fontBody, fontWeight: 500, fontSize: '0.89rem', lineHeight: 1.3, letterSpacing: '0em' },
  body1: { fontFamily: fontBody, fontWeight: 400, fontSize: '1.1rem', lineHeight: 1.5, letterSpacing: '0em' },
  body2: { fontFamily: fontBody, fontWeight: 400, fontSize: '.9rem', lineHeight: 1.5, letterSpacing: '0em' },
  button: { fontFamily: fontBody, fontWeight: 400, fontSize: '1rem', lineHeight: 1.2, letterSpacing: '0em' },
  caption: { fontFamily: fontBody, fontWeight: 400, fontSize: '0.8rem', lineHeight: 1.3, letterSpacing: '0em' },
  overline: { fontFamily: fontBody, fontWeight: 400, fontSize: '0.8rem', lineHeight: 1.4, letterSpacing: '0em' },
};

// NOTE on TypeScript: these theme files are plain .js, matching the
// existing scaffold's convention. The custom palette keys below
// (dragonGreen/campusGreen/trustTeal/coral) work fine at runtime from a
// .tsx component (`theme.palette.dragonGreen.main`), but won't get
// TS autocomplete/type-checking unless the project also augments MUI's
// `Palette`/`PaletteOptions` interfaces via `declare module
// '@mui/material/styles'` — add that separately only if a generated app
// is strict enough to need it; not required for these templates to work.
