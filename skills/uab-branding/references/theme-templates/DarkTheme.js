import { createTheme, responsiveFontSizes } from '@mui/material/styles';
import { focusRingComponents, noTextTransformComponents, reducedMotionCssBaseline, typographyVariants } from './themeShared';

/*
 * UAB OFFICIAL BRAND PALETTE — DARK MODE
 * Source of truth: MyUABPortal (UAB's real production portal), verified
 * directly against its shipped theme implementation — not re-fetched from
 * the public brand guide site. See ../../palette.md for the full palette
 * and the trimmed-core-set decision record.
 *
 * Same brand colors as LightTheme.js — what changes in dark mode is
 * background/paper (paper == primary.main here) and the focus-ring
 * outline color (white instead of Dragon's Lair Green, for contrast
 * against dark backgrounds).
 *
 * FONTS: identical mapping to LightTheme.js — see ../../typography.md.
 */

export const DarkTheme = responsiveFontSizes(createTheme({
  palette: {
    mode: 'dark',
    primary: {
      main: '#1A5632',
      light: '#185843',
      dark: '#033319',
      contrastText: '#fff',
    },
    secondary: { main: '#033319' },
    dragonGreen: { main: '#033319' },
    campusGreen: { main: '#90D408' },
    trustTeal: { main: '#68C6B8' },
    coral: { main: '#ea6852' },
    error: { main: '#c7ba9b', light: '#e3ddcd', dark: '#aa9767' },
    // Same intentional ordering caveat as LightTheme.js — see there.
    warning: { main: '#ffe357', light: '#fff1ab', dark: '#ffd400' },
    info: { main: '#80bc00' },
    success: { main: '#80BC00' },
    background: { default: '#022b1a', paper: '#1A5632' },
    divider: '#558674',
  },
  typography: typographyVariants,
  components: {
    ...focusRingComponents('#fff'),
    ...noTextTransformComponents,
    ...reducedMotionCssBaseline,
  },
}));
