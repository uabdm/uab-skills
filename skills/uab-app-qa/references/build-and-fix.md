# Build & lint

Run `npm run build`. This is a real production build (TypeScript type
checking, import resolution, and — depending on the project's config —
lint-as-build-error), not a dev-server compile, so it catches classes of
bug the dev server's incremental compiler can be lazier about. Then run
`npm run lint` if the project defines that script separately.

**Read the full error, including the file:line, before proposing a fix.**
A build error message that looks familiar from general Next.js/React
experience can still be wrong for this specific error, especially given
this app's Next.js version may carry breaking changes from what training
data assumes — see SKILL.md's "this Next.js is not the Next.js you know"
note. If the error is anywhere near routing, server actions, `headers()`/
`cookies()`/`params`, metadata, or middleware, check
`node_modules/next/dist/docs/` for that app's actual installed version
before assuming you know the fix.

## Common categories in a generated Next.js + MUI app

- **Import resolution.** A path alias (`@/...`) not matching
  `tsconfig.json`'s `paths`, or a file referenced with the wrong
  case/extension. Confirm the actual file exists at the exact path/case
  before assuming the import statement is wrong.
- **Type errors from strict TypeScript config.** Fix the actual type
  mismatch (a missing prop, a wrong shape) — don't reach for `any` or
  `// @ts-ignore` as a shortcut. If the error is inside a third-party
  type definition that's genuinely wrong, that's rare enough to warrant
  double-checking your own usage first.
- **`'use client'`/`'use server'` boundary violations** — a client-only
  hook (`useState`, `useEffect`, `useMediaQuery`, event handlers) used in
  a file without `'use client'`, or a server-only API used in a client
  component. The fix is almost always adding/moving the directive or
  splitting the component, not changing the API usage itself.
- **Async dynamic APIs.** Recent Next.js versions made some App Router
  APIs (`headers()`, `cookies()`, and in some versions route `params`)
  asynchronous where they previously weren't. A build or type error
  pointing at one of these is a strong signal to check
  `node_modules/next/dist/docs/` for this exact version's signature rather
  than assuming the synchronous form from training data.
- **Lint-as-error.** Unused variables/imports, missing `key` props in
  lists, exhaustive-deps warnings promoted to errors. Fix the actual
  code (remove the unused import, add the real dependency) — don't add an
  `eslint-disable` comment to silence it unless the rule is a genuine
  false positive, and say explicitly why if you do.

## Hard rule

Loop: fix the real defect in source, rebuild, confirm the specific error
is gone AND no new one appeared, repeat until `npm run build` (and `npm
run lint`, if present) both exit clean. Don't move on to Phase 3 with a
build that "mostly" passes or that you talked yourself into accepting with
a suppression.
