# Data Layer — works with zero configuration, locally and in Azure

Only when data storage was chosen (Q6 = A or C — see DATA STORAGE in
`decision-matrix.md`). The goal: the project leader never sees a connection
string. The app must run locally with no setup and run in Azure with no
setup. Achieve this with an "env-or-fallback" pattern in the config/data
files plus automatic provisioning in Bicep (`infra-bicep.md`).

## Azure SQL (structured storage)

- Config reads `DATABASE_URL` from the environment.
  - If set (Azure — injected from Key Vault), connect using `mssql`.
    **CONNECTION STRING FORMAT — this bites:** `mssql@12`
    (`sql.connect(string)`) parses a *string* config ONLY as the ADO.NET
    format (via `@tediousjs/connection-string`) — it has NO `mssql://` URI
    parser. The provisioned `DATABASE_URL` (see `sql.bicep` in
    `infra-bicep.md`) must be
    `Server=tcp:<fqdn>,1433;Initial Catalog=<db>;User ID=<login>;Password=<pw>;Encrypt=true`,
    NOT `mssql://user:pass@host:1433/db`. A URI leaves `server` undefined and
    the driver throws "The config.server property is required and must be
    of type string" (surfacing as a 401 from the API route). Alternatively
    pass a config OBJECT to `sql.connect`, which skips string parsing
    entirely.
  - If NOT set (developer's laptop), fall back to a local SQLite file (e.g.
    `./.data/local.db`) using Node's BUILT-IN `node:sqlite` module (its
    `DatabaseSync` class) — NOT a native addon like `better-sqlite3`. This is
    load-bearing, do not "upgrade" it back to `better-sqlite3`:
    `better-sqlite3` needs a C++ build toolchain to compile from source (a
    machine without Visual Studio/Xcode CLT can't install it), and its
    native `.node` binary is what creates Windows junction files under
    `.next/` that break the remote-build tar step. `node:sqlite` has no
    native compile step and ships with Node itself. It requires Node >= 22 —
    see PACKAGE VERSIONING in `scaffold-web-nextjs.md` and the Dockerfile
    (both on `node:22-alpine` or newer). Load it with a DYNAMIC import from
    inside the fallback function only, so it's never touched on the Azure
    SQL path:
    ```ts
    import type { DatabaseSync } from 'node:sqlite';
    const { DatabaseSync: Sqlite } = await import('node:sqlite');
    const db = new Sqlite(path.join(dataDir, 'local.db'));
    ```
    Create the `.data` directory + file automatically (`fs.mkdirSync`
    recursive). No dependency to install, no setup required.
- On startup, auto-create the sample schema if it doesn't exist (a single
  table such as `items` with id + a couple of columns). No manual migration
  step.
- Generate a tiny but REAL data flow: one page/route that lists rows and a
  form/button that inserts a row, wired to the data layer above. Mark the
  place for real domain logic with a TODO, but create + list must actually
  work end to end.
- Next.js note: `node:sqlite` and `mssql` are server-only. Use them inside
  Route Handlers (`app/api/.../route.ts`) or server actions, never in client
  components.

## Azure Blob Storage (file/upload storage)

- Config reads `AZURE_STORAGE_CONNECTION_STRING` from the environment.
  - If set (Azure), use `@azure/storage-blob`.
  - If not set (local), fall back to reading/writing files under
    `./.localstorage`, creating the directory automatically.
- Provide a small helper with `save(name, bytes)` and `list()` that works
  against whichever backend is active. Leave domain logic as a TODO.

## Local fallback artifacts

- Add `.data/` and `.localstorage/` to `.gitignore`, written WITHOUT a
  leading `./` — `./.data/` is not valid gitignore syntax and silently
  matches nothing, which would let the local SQLite database get committed
  by accident.
- These fallbacks exist ONLY so the app runs locally with zero
  configuration; in Azure the real services are always used.

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
real secret a developer fills in locally (database/storage overrides,
external-integration test credentials — see `.env.local` in
`auth-hydra-oidc.md` and `decision-matrix.md`) lives in one of these files,
never in `.env.template`, so a gap here is a real path for a secret to get
committed by accident. Confirm this in `verification-checklist.md`.

## `.dockerignore` — generate at the repo root, ALWAYS

Not optional polish: the scaffold deploys with `remoteBuild: true` (see
`azure-yaml.md`), so `azd` tars the ENTIRE build context and ships it to ACR
to build there. Without a `.dockerignore` that context is the whole project —
tens of thousands of files including `node_modules/`, `.git/`, `.next/`,
`.env.local`, and the local `.data/` database — both a correctness bug and a
secret leak:

- **Correctness:** the Dockerfile runs `npm ci` (or `pip install`) INSIDE the
  image and then `COPY . .`. If `node_modules/` isn't excluded, the host's
  (Windows/macOS) modules overwrite the Linux ones installed in the image.
  Even with `node:sqlite` (no native addon of our own), transitive native
  deps can still land the wrong-OS binary in an Alpine container and crash
  at runtime — so excluding `node_modules` is mandatory regardless.
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
# azd / tooling state and docs (hygiene — smaller build context).
.azure
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
.azure
.claude
.vscode
*.md
!README.md
```

Load-bearing vs. hygiene (so it can be adapted per project): `node_modules`
(web) / `.venv`, `__pycache__` (Python) and `.next` (web) are CRITICAL —
omitting them reintroduces the host-overwrites-container bug (and, on
Windows + a native SQLite addon, a tar failure). `.env*`, `.data`,
`.localstorage` are security/correctness — always keep. `.git`, `.azure`,
`.claude`, `.vscode`, `*.md` are pure hygiene; `!README.md` re-includes the
README some tooling expects. Adjust these freely. Confirm this file exists
in `verification-checklist.md`.
