# ARIA patterns

Verified, real examples from `MyUABPortal` — not invented. Apply the
matching pattern whenever a generated (or audited) component fits one of
these shapes.

## Icon-only button

Decorative icon gets `aria-hidden="true"`; the accessible name comes from
`aria-label` on the button, never from the icon alone or from a `Tooltip`
alone (see `color-and-status.md` for why tooltip-only is a fail).

```tsx
<IconButton color="inherit" onClick={handleClick} aria-label="Open notifications">
  <NotificationsIcon aria-hidden="true" />
</IconButton>
```

Dynamic/state-aware label when the button's meaning changes:

```tsx
aria-label={`Notifications${newMessageCount > 0 ? ` (${newMessageCount} new)` : ''}`}
```

## Menu trigger

```tsx
<IconButton
  aria-controls={isMenuOpen ? 'menu-appbar' : undefined}
  aria-haspopup="true"
  aria-expanded={isMenuOpen ? 'true' : undefined}
  onClick={handleOpen}
>
```

Don't manually set `role="menu"`/`role="dialog"` on MUI `Menu`/`Dialog` —
those components apply the correct role internally; adding your own is
redundant and can conflict.

## Active/current state (pagination, nav)

```tsx
aria-current={currentPage === page ? 'page' : undefined}
```

## Landmark nav labeling

```tsx
<Box component="nav" aria-label="Primary <app name> navigation">
```

## Async loading / error state (live regions)

```tsx
<Box role="status" aria-label="Loading <what>…">
  <CircularProgress />
</Box>
```

```tsx
{/* role="alert" announces the error to screen readers immediately */}
<Box role="alert">{errorMessage}</Box>
```

For a page-level busy indicator that isn't tied to one specific region:

```tsx
<Box role="status" aria-live="polite" aria-atomic="true" aria-busy="true">
```

## Tab / tab panel wiring

The `id`/`aria-controls`/`aria-labelledby` triplet ties each tab to its
panel:

```tsx
function a11yProps(index) {
  return { id: `tab-${index}`, 'aria-controls': `tabpanel-${index}` };
}

<Tabs aria-label="<app name> tabs">
  <Tab label="First" {...a11yProps(0)} />
</Tabs>
<Box role="tabpanel" id={`tabpanel-0`} aria-labelledby={`tab-0`}>...</Box>
```

## Decorative images/swatches

```tsx
<span aria-hidden="true" style={{ backgroundColor: entry.fill }} />
```

and for a purely decorative `<img>` (headline text rendered separately as
a sibling, so the image adds nothing on its own):

```tsx
<img src={imageSrc} alt="" />
```

## `role=` values actually verified in production use

`status`, `alert`, `tabpanel`, `main` — stick to these plus whatever MUI
sets internally (`dialog`, `menu`, etc., via `Dialog`/`Menu`). Don't invent
ARIA roles beyond what's needed for the pattern at hand.
