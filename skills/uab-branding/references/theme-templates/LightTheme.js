import { createTheme, responsiveFontSizes } from '@mui/material/styles';
import { focusRingComponents, noTextTransformComponents, reducedMotionCssBaseline, typographyVariants } from './themeShared';

/*
 * UAB OFFICIAL BRAND PALETTE — LIGHT MODE
 * Source of truth: MyUABPortal (UAB's real production portal), verified
 * directly against its shipped theme implementation — not re-fetched from
 * the public brand guide site. See ../../palette.md for the full palette
 * and the trimmed-core-set decision record.
 *
 * PRIMARY
 *   UAB Green            #1A5632
 *   Dragon's Lair Green  #033319   (secondary.main / dragonGreen.main)
 *
 * CORE ACCENTS
 *   Campus Green         #90D408
 *   Trust Teal           #68C6B8
 *   Coral                #ea6852
 *
 * FONTS (Adobe Fonts / Typekit — org kit ygy8wyj, see ../../typography.md)
 *   Headings (h1, h3 only): 'kulturista-web', sans-serif
 *   Everything else:        'proxima-nova', 'Helvetica', 'Arial', sans-serif
 *
 * WCAG 2.1 AA: focus-ring outline color in light mode is Dragon's Lair
 * Green (#033319) — see themeShared.js for the shared focus-ring pattern
 * applied below.
 */

export const LightTheme = responsiveFontSizes(createTheme({
  palette: {
    mode: 'light',
    primary: {
      main: '#1A5632',
      light: '#F4F4F4',
      dark: '#033319',
      contrastText: '#fff',
    },
    secondary: { main: '#033319' },
    dragonGreen: { main: '#033319' },
    campusGreen: { main: '#90D408' },
    trustTeal: { main: '#68C6B8' },
    coral: { main: '#ea6852' },
    error: { main: '#c7ba9b', light: '#e3ddcd', dark: '#aa9767' },
    // NOTE: `main` is intentionally the lightest of the three here —
    // copied faithfully from the portal's own (unusual) ordering. Don't
    // "fix" this without re-checking the portal first.
    warning: { main: '#ffe357', light: '#fff1ab', dark: '#ffd400' },
    info: { main: '#80bc00' },
    success: { main: '#80BC00' },
    background: { default: '#F2F2F3', paper: '#ffffff' },
    divider: '#D3D3D3',
    // Portal's LightTheme.js hardcodes `color: '#1A5632'` on every single
    // typography variant (h1-h6, body1, body2, button, caption...) plus
    // `typography.color` at the top level — MUI v4-era belt-and-suspenders.
    // typographyVariants below intentionally doesn't repeat that per
    // variant (v5 idiom: let Typography inherit palette.text.primary
    // instead). That ONLY works if text.primary is actually set here —
    // leaving it unset silently falls back to MUI's own default
    // (rgba(0,0,0,0.87), i.e. near-black), not UAB Green. Confirmed bug in
    // uab-app-creator-nobrand-helloworld's generated homepage: "Welcome!"
    // rendered black because this line was missing. See palette.md.
    text: { primary: '#1A5632' },
  },
  typography: typographyVariants,
  components: {
    ...focusRingComponents('#033319'),
    ...noTextTransformComponents,
    ...reducedMotionCssBaseline,
  },
}));
