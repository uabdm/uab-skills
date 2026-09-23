# Common bug patterns

A running catalog of confirmed runtime bugs found in generated apps, with
their actual fix — check here before re-deriving a diagnosis from
scratch. Add to this file whenever this skill finds and fixes something
new; that's the whole point of keeping it (see `uab-branding`'s own
reference files for the same "confirmed bug" pattern this catalog
follows).

Brand-color, typography-scale, landmark, and focus-ring bugs are
`uab-branding`'s territory — its `references/audit-checklist.md` and
`references/landmarks-and-structure.md` already catalog several confirmed
ones (missing `palette.text.primary`, missing `fontSize` on typography
variants, a `Drawer` wrapped in an extra `<Box component="nav">` breaking
its full-height fill). Run that skill's AUDIT mode for those instead of
duplicating them here. This file is for defects that show up at runtime/in
the browser and aren't specifically about UAB branding.

## MUI component already defaults its own `component` prop to a heading tag

**Symptom:** Next.js hydration error, `In HTML, <hN> cannot be a child of
<hN>` (or a mismatched pair), thrown the instant a component mounts —
often a dialog, since this is easy to trigger by opening one.

**Confirmed case:** `DialogTitle` hardcodes `component: "h2"` internally
(verified at `@mui/material/DialogTitle/DialogTitle.js`). The footer
template in `uab-branding` nested a `<Typography variant="h5"
component="h2">` directly inside it — a literal `<h2>` inside `<h2>`. Fix:
drop the inner `component="h2"` (use `component="span"` if you need to
override the rendered tag at all) — `DialogTitle`'s own `<h2>` already
provides the accessible heading name via `aria-labelledby`; the inner
`Typography` only needs to carry the visual size.

**General check:** before adding an explicit `component="h#"` to a
`Typography` (or anything else with a `component` prop) nested inside
another MUI component, check whether the *outer* component already
defaults to a heading tag. `DialogTitle` (`h2`) is the confirmed one;
`AccordionSummary`, `CardHeader`'s `title` prop, and similar
"already-semantic" wrappers are worth the same one-line check before
nesting another explicit heading inside them.

## `useMediaQuery`-gated SSR/hydration mismatches

`useMediaQuery` returns `false` on the server (no `matchMedia` available)
and only resolves to the real value after client hydration. If a component
uses it to decide between two *structurally different* trees (not just a
style difference), the server-rendered HTML and the first client render
can disagree, which React flags as a hydration mismatch. This is usually
fine for something like switching a `Drawer`'s `variant` prop (MUI already
handles that internally), but worth checking if a hydration warning points
at a component built around a raw `useMediaQuery` conditional. MUI's
`useMediaQuery` takes a `{ noSsr: true }` option for cases where the
server-rendered value genuinely doesn't matter (it always causes an extra
client-only re-render instead of trying to match SSR output) — reach for
that only after confirming the mismatch is actually coming from this
pattern, not as a reflexive fix.

## Next.js App Router async dynamic APIs

Some Next.js versions made previously-synchronous App Router APIs
(`headers()`, `cookies()`, and in some versions route `params`)
asynchronous. A build or runtime error where one of these is used without
`await` is a strong signal to check that app's own
`node_modules/next/dist/docs/` for the installed version's actual
signature — see `SKILL.md`'s "this Next.js is not the Next.js you know"
note — rather than assuming the synchronous form from general Next.js
familiarity.
