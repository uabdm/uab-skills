# Forms

## What the portal does (extract and keep)

Every field gets a real, visible `label` — never a placeholder used as a
substitute for a label:

```tsx
<TextField fullWidth id="outlined-name" label="Search by Name" autoComplete="name" />
```

`Checkbox` accessible names come from `FormControlLabel` wrapping, not a
`label` prop directly on `Checkbox` (MUI's `Checkbox` has no `label` prop —
setting one is silently ignored, which is a latent bug found in the
portal's own `CheckBoxList.js`; don't copy that mistake):

```tsx
<FormControlLabel control={<Checkbox checked={checked} onChange={onChange} />} label={item.Name} />
```

Required + invalid state, where the portal does wire it:

```tsx
<TextField
  variant="filled"
  required
  fullWidth
  label="Name"
  value={name}
  onChange={handleNameField}
  inputProps={{ 'aria-required': true, 'aria-invalid': isNameInvalid }}
/>
```

## What this skill adds (the portal has no example of this — don't look
for one)

The portal has **no** `helperText`/MUI `error`-prop pattern anywhere in its
codebase — this is a gap in the source of truth itself, not something to
extract. Introduce a proper error-messaging convention for generated
forms instead of leaving it unhandled:

```tsx
<TextField
  label="Email"
  value={email}
  onChange={handleEmailChange}
  required
  error={isEmailInvalid}
  helperText={isEmailInvalid ? 'Enter a valid email address.' : ' '}
  inputProps={{ 'aria-required': true, 'aria-invalid': isEmailInvalid }}
  FormHelperTextProps={{ id: 'email-helper-text' }}
  aria-describedby="email-helper-text"
/>
```

- `error={boolean}` drives MUI's own red-outline/red-helper-text styling —
  don't also hand-roll error coloring with a raw hex.
- `helperText` renders a space (`' '`) rather than `undefined` when there's
  no error, so the field's height doesn't jump when an error appears —
  don't let helper text pop the layout.
- `aria-describedby` pointing at the helper text's `id` is what actually
  connects the error message to the field for a screen reader — `error`/
  `helperText` alone are visual only.

## Audit-mode check

- Every `TextField`/`Select` has a `label` (or `aria-label` if a visible
  label genuinely isn't appropriate — rare, flag for review rather than
  auto-failing).
- Every `Checkbox`/`Radio` is wrapped in `FormControlLabel`, not given a
  bare (non-functional) `label` prop directly.
- Any field with validation has `error`, `helperText`, and a matching
  `aria-describedby` — not just a red border with no text explanation.
