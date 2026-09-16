# Data Layer — local storage, zero configuration

Only when data storage was chosen (Q6 = A or C — see DATA STORAGE in
`decision-matrix.md`). This skill generates no cloud infrastructure, so data
storage is always a real, working LOCAL implementation — the project leader
never sees a connection string and nothing needs installing.

## Structured data (records/lists)

- Use a local SQLite file (`./.data/local.db`) via Node's BUILT-IN
  `node:sqlite` module (its `DatabaseSync` class) — NOT a native addon like
  `better-sqlite3`. This is load-bearing, do not "upgrade" it back to
  `better-sqlite3`: `better-sqlite3` needs a C++ build toolchain to compile
  from source (a machine without Visual Studio/Xcode CLT can't install it),
  and its native `.node` binary is a common source of platform-specific
  breakage when the zip is unpacked on a different machine than it was
  generated on. `node:sqlite` has no native compile step and ships with Node
  itself. It requires Node >= 22 — see PACKAGE VERSIONING in
  `scaffold-web-nextjs.md` and the Dockerfile (both on `node:22-alpine` or
  newer). Load it with a DYNAMIC import:
  ```ts
  import type { DatabaseSync } from 'node:sqlite';
  const { DatabaseSync: Sqlite } = await import('node:sqlite');
  const db = new Sqlite(path.join(dataDir, 'local.db'));
  ```
  Create the `.data` directory + file automatically (`fs.mkdirSync`
  recursive). No dependency to install, no setup required.
- (Python worker) Use the stdlib `sqlite3` module the same way — same file
  location, same auto-create behavior, no extra dependency.
- On startup, auto-create the sample schema if it doesn't exist (a single
  table such as `items` with id + a couple of columns). No manual migration
  step.
- Generate a tiny but REAL data flow: one page/route that lists rows and a
  form/button that inserts a row, wired to the data layer above. Mark the
  place for real domain logic with a TODO, but create + list must actually
  work end to end.
- Next.js note: `node:sqlite` is server-only. Use it inside Route Handlers
  (`app/api/.../route.ts`) or server actions, never in client components.

## File / upload storage

- Read and write files under `./.localstorage`, creating the directory
  automatically.
- Provide a small helper with `save(name, bytes)` and `list()` that works
  against this local backend. Leave domain logic as a TODO.

## If this app is later deployed somewhere permanent

Swapping either of these for a hosted database or storage account is a
follow-up step for whoever deploys the app for real — out of scope for this
skill. Leave a short comment at the top of the data/config file noting this
so a future developer knows where to make that change; do not build a
dual local/cloud fallback pattern for a cloud target this skill never
provisions.

## Local artifacts

- Add `.data/` and `.localstorage/` to `.gitignore` (in case the project
  leader's team later puts this folder under git themselves), written
  WITHOUT a leading `./` — `./.data/` is not valid gitignore syntax and
  silently matches nothing.
- `scripts/package-app.sh` also excludes both of these directories from the
  handoff zip directly — the zip should never ship a local SQLite file or
  uploaded test files from the machine that generated it.

## `.gitignore` — generate at the repo root, always

Web app (Next.js):
```
node_modules/
.next/
.env
.env*.local
.data/
.localstorage/
```

Worker (Python):
```
__pycache__/
.venv/
.env
.data/
.localstorage/
```

`.env` and `.env*.local` must both be covered — not just `.env.local`. Every
real secret a developer fills in locally (external-integration test
credentials — see `.env.local` in `auth-hydra-oidc.md` and
`decision-matrix.md`) lives in one of these files, never in `.env.template`,
so a gap here is a real path for a secret to get committed by accident if
the project leader's team later puts this folder under git. Confirm this in
`verification-checklist.md`.

## `.dockerignore` — generate at the repo root, ALWAYS

Not optional polish: without it, `docker build` sends the ENTIRE project
directory as the build context — tens of thousands of files including
`node_modules/`, `.git/`, `.next/`, `.env.local`, and the local `.data/`
database — both a correctness bug and a secret leak:

- **Correctness:** the Dockerfile runs `npm ci` (or `pip install`) INSIDE the
  image and then `COPY . .`. If `node_modules/` isn't excluded, the host's
  (Windows/macOS) modules overwrite the Linux ones installed in the image and
  crash at runtime — excluding `node_modules` is mandatory regardless.
- **Secrets/data:** `.env`, `.env*.local`, and the local `.data/` SQLite
  file must never reach a published, potentially shareable image.

Web app (Next.js) — write exactly this at the repo root:
```
# Build artifacts and dependencies — the image rebuilds these itself.
node_modules
.next
out
.git
.gitignore
# Local-only data and secrets — must never reach the image.
.data
.localstorage
.env
.env.local
.env*.local
# tooling state and docs (hygiene — smaller build context).
.claude
.vscode
*.md
!README.md
```

Worker (Python) — same idea, swap the JS build dirs for the Python ones:
```
__pycache__
.venv
.git
.gitignore
.data
.localstorage
.env
.env.local
.env*.local
.claude
.vscode
*.md
!README.md
```

Load-bearing vs. hygiene (so it can be adapted per project): `node_modules`
(web) / `.venv`, `__pycache__` (Python) and `.next` (web) are CRITICAL —
omitting them reintroduces the host-overwrites-container bug. `.env*`,
`.data`, `.localstorage` are security/correctness — always keep. `.git`,
`.claude`, `.vscode`, `*.md` are pure hygiene; `!README.md` re-includes the
README some tooling expects. Adjust these freely. Confirm this file exists
in `verification-checklist.md`.
