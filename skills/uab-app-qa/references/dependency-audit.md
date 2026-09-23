# Dependency install & audit

Run `scripts/install-and-audit.sh` from the app's repo root. It runs `npm
install`, then `npm audit fix` (non-breaking fixes only), then `npm audit
--audit-level=high` and fails loudly if anything high/critical remains
unresolved. Treat any failure as something to actually fix, not a script
to route around — if the script itself won't run in the current
environment, run the same three commands by hand rather than skipping the
step.

## When `npm install` itself fails

Read the actual error before reaching for a flag. In order of how often
each is the real cause in a generated Next.js+MUI app:

1. **Peer dependency conflict.** Most commonly the generated app pins a
   very recent React (these apps use `^19.3.0`) against a library whose
   published peer range hasn't caught up yet. Check the specific package's
   actual peer range (`npm info <package> peerDependencies`) before
   assuming it's broken — MUI's own packages track new React majors
   quickly, so a conflict is more often a *different*, smaller dependency
   in the tree. Fix by bumping the conflicting package to a version whose
   peer range covers the installed React, not by reaching for
   `--legacy-peer-deps` as a first move — that flag silences the warning
   without resolving the actual incompatibility, and can let a genuinely
   broken pairing install successfully and fail at runtime instead, which
   is harder to diagnose than the install-time error would have been. Only
   use it once you've confirmed by reading the peer range that the
   conflict is a false positive (e.g. a library that hasn't bumped its
   declared range yet but is actually fine), and say so explicitly when
   you do.
2. **Lockfile drift.** `package-lock.json` out of sync with `package.json`
   (common if a dependency was hand-edited). `npm install` regenerates it;
   if `npm ci` is what the app's own scripts/Dockerfile actually use,
   confirm that path works too, not just plain `npm install`.
3. **A genuinely deprecated/renamed package.** Check the package's own
   npm page or GitHub for its current name/replacement before assuming the
   version number alone is the fix.
4. **`engines` mismatch** (a package requiring a newer Node than what's
   installed in this environment). Confirm the actual Node version
   (`node --version`) against what the failing package declares.

Never delete `package-lock.json` to "make the conflict go away" — that
discards the exact dependency resolution the app was generated and tested
against, and can silently pull in different transitive versions than what
shipped. Investigate the actual conflict instead.

## `npm audit` findings

`npm audit fix` (no `--force`) handles same-major-version patches
automatically — always run this first. For anything it can't resolve:

- Read the advisory. Confirm the flagged package is actually reachable
  from app code (a `devDependency` used only by the build tooling is a
  different risk profile than something bundled into the shipped app).
- If the fix requires a major version bump, check that package's
  changelog/release notes for breaking changes before applying it — a
  major bump can fix one vulnerability and introduce a different runtime
  break (a prop rename, a removed export) that Phase 2/3 will then have to
  catch and you'll have to re-diagnose. Apply the bump deliberately, then
  immediately re-run Phase 2 (build) to catch anything the bump broke,
  rather than deferring that check to later.
- `npm audit fix --force` is a last resort, never a default move — only
  after you've read what it intends to change and confirmed the breaking
  changes (if any) don't affect how this app actually uses the package.
- If a high/critical finding genuinely can't be resolved (no patched
  version exists yet, or the only fix is a downgrade that breaks something
  else), say so explicitly in the Phase 5 report — don't silently leave it
  and call the pass clean.
