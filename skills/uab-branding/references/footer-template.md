# Footer template

Adapted from `MyUABPortal/src/Containers/Portal/Bottom/Footer/Footer.js`
(the real production footer) — translated to a Next.js/TypeScript
functional component, using theme tokens instead of the portal's mix of
theme tokens and raw hex, and using the simplified link set the user chose
over matching the portal exactly (no "A-Z Site Index" — generated demo
apps don't have enough content to warrant it).

**Links used (exactly these, in this order — do not add, omit, or
reorder):** Nondiscrimination Statement (dialog, not a link) → Contact UAB
→ Privacy → Terms of Use → copyright line. Every generated app gets this
exact footer — it is a fixed platform requirement, not derived from the
project leader's answers.

## `Footer.tsx`

```tsx
'use client';
import React from 'react';
import { Box, Button, Link, Typography, Dialog, DialogTitle, DialogContent, IconButton, Divider, Grid, useMediaQuery } from '@mui/material';
import CloseIcon from '@mui/icons-material/Close';
import { useTheme } from '@mui/material/styles';

const CONTACT_URL = 'https://www.uab.edu/home/contact';
const PRIVACY_URL = 'https://www.uab.edu/privacy/statements';
const TERMS_URL = 'https://www.uab.edu/toolkit/web/terms-of-use';
const TITLE_IX_URL = 'https://uab.edu/titleix';

function NondiscriminationDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <Typography variant="h5" component="h2">Nondiscrimination Statement</Typography>
        <IconButton aria-label="Close" onClick={onClose}>
          <CloseIcon />
        </IconButton>
      </DialogTitle>
      <Divider />
      <DialogContent>
        <Typography variant="body1" component="p">
          UAB is an Equal Employment/Equal Educational Opportunity Institution dedicated to providing equal opportunities and equal access to all individuals regardless of race, color, religion, ethnic or national origin, sex (including pregnancy), genetic information, age, disability, and veteran&rsquo;s status. As required by Title IX, UAB prohibits sex discrimination in any education program or activity that it operates. Individuals may report concerns or questions to UAB&rsquo;s Assistant Vice President and Senior Title IX Coordinator. The Title IX notice of nondiscrimination is located at{' '}
          <Link href={TITLE_IX_URL} target="_blank" rel="noopener noreferrer" sx={{ textDecoration: 'underline' }}>
            uab.edu/titleix
          </Link>.
        </Typography>
      </DialogContent>
    </Dialog>
  );
}

export default function Footer() {
  const theme = useTheme();
  const isMobile = useMediaQuery(theme.breakpoints.down('sm'));
  const [dialogOpen, setDialogOpen] = React.useState(false);

  return (
    <Box
      component="footer"
      sx={{
        p: 3,
        backgroundColor: 'background.default',
        borderTop: '1px solid',
        borderColor: 'divider',
        mt: 'auto',
      }}
    >
      <Grid
        container
        spacing={2}
        justifyContent="center"
        alignItems="center"
        direction={isMobile ? 'column' : 'row'}
        sx={{ textAlign: 'center' }}
      >
        <Grid item>
          <Button
            variant="contained"
            size="small"
            onClick={() => setDialogOpen(true)}
            sx={{
              backgroundColor: 'dragonGreen.main',
              color: 'primary.contrastText',
              '&:hover': { backgroundColor: 'dragonGreen.main', opacity: 0.9 },
            }}
          >
            Nondiscrimination Statement
          </Button>
        </Grid>
        <Grid item>
          <Link href={CONTACT_URL} target="_blank" rel="noopener noreferrer" underline="hover" color="text.primary" sx={{ fontSize: '0.875rem' }}>
            Contact UAB
          </Link>
        </Grid>
        <Grid item>
          <Link href={PRIVACY_URL} target="_blank" rel="noopener noreferrer" underline="hover" color="text.primary" sx={{ fontSize: '0.875rem' }}>
            Privacy
          </Link>
        </Grid>
        <Grid item>
          <Link href={TERMS_URL} target="_blank" rel="noopener noreferrer" underline="hover" color="text.primary" sx={{ fontSize: '0.875rem' }}>
            Terms of Use
          </Link>
        </Grid>
        <Grid item>
          <Typography variant="caption" color="text.secondary">
            © {new Date().getFullYear()} The University of Alabama at Birmingham
          </Typography>
        </Grid>
      </Grid>

      <NondiscriminationDialog open={dialogOpen} onClose={() => setDialogOpen(false)} />
    </Box>
  );
}
```

## Why this differs from the previously-generated version

`timeoff-demo-app-slim-litelllm`'s `Footer.tsx` hardcoded the button hover
color as `backgroundColor: '#033319'` — a raw hex with no theme
connection. This template uses `theme.palette.dragonGreen.main` (via the
`sx` shorthand string `'dragonGreen.main'`) instead, relying on the
`dragonGreen` palette token defined in `theme-templates/LightTheme.js`/
`DarkTheme.js`. If a future edit needs a UAB color not yet in the palette,
add it to the theme file first — never reach for a literal hex in a
component.

The Nondiscrimination dialog's close button, and every link, inherit their
focus ring automatically from the theme's `MuiButtonBase`/`MuiLink`
overrides (see `focus-and-motion.md`) — nothing extra needed here.

## Audit-mode check

- Confirm the link set matches exactly (Nondiscrimination, Contact UAB,
  Privacy, Terms of Use, copyright) — flag any extra or missing link.
- Confirm the Nondiscrimination Statement dialog's title and body text
  match verbatim (a paraphrase or shortened version is a fail — the
  guideline is explicit that this text must not be paraphrased).
- Grep `Footer.tsx` (or wherever the footer lives) for a raw hex string —
  flag any color not expressed as a `theme.palette.*` reference.
