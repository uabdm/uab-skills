# Color and status indicators

## Never color alone (WCAG 2.1 AA, SC 1.4.1 Use of Color)

Source: `MyUABPortal/src/Components/Status/Status.js:256-506`. Every
status/state gets a **distinct icon shape** *and* a **text label**, color
is never the only signal:

```tsx
<Tooltip title={statusLabel}>
  {statusType === OPERATIONAL ? <CheckboxMarkedCircleOutlineIcon /> :
   statusType === DEGRADED ? <SpeedometerSlowIcon sx={{ color: 'warning.dark' }} /> :
   statusType === MAINTENANCE ? <ToolsIcon color="primary" /> :
   statusType === INFO ? <InformationOutlineIcon sx={{ color: 'certifiedgold.main' }} /> :
   <AlertDecagramOutlineIcon sx={{ color: 'coral.main' }} />}
</Tooltip>
```

Pair every color-coded indicator with an explicit text legend somewhere on
the page — don't rely on the icon+color combination alone to carry the
full meaning for a first-time user:

```tsx
<Stack direction="row" spacing={1} alignItems="center">
  <CheckboxMarkedCircleOutlineIcon aria-hidden="true" />
  <Typography variant="body2">Operational</Typography>
</Stack>
```

## Tooltip is not a substitute for `aria-label` (counter-example)

`MyUABPortal/src/Containers/Portal/Top/RightMenuActions/OnHoldAction/OnHoldAction.js:39-45`
is the documented anti-pattern to avoid: an icon-only button colored via a
raw inline hex, wrapped in `Tooltip title="OnHold"`, with **no**
`aria-label` on the `IconButton` itself. A `Tooltip` is not reliably
announced by every screen reader in every interaction mode — the
accessible name must come from `aria-label` (or visible text) directly on
the interactive element, with the tooltip as a visual bonus, not the sole
mechanism:

```tsx
{/* WRONG — do not generate this */}
<Tooltip title="On hold">
  <IconButton sx={{ color: '#D3492B' }}><LightbulbIcon /></IconButton>
</Tooltip>

{/* RIGHT */}
<Tooltip title="On hold">
  <IconButton aria-label="On hold" sx={{ color: 'warning.dark' }}>
    <LightbulbIcon aria-hidden="true" />
  </IconButton>
</Tooltip>
```

## Audit-mode check

- Any status/state UI driven by color: confirm it also carries a distinct
  icon shape and/or visible text — flag color-only indicators (badges,
  dots, colored text with no icon/label) as a fail.
- Every icon-only `IconButton`: confirm `aria-label` is present directly on
  the button, not only inside a wrapping `Tooltip`.
