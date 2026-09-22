# Decision Matrix

Apply this silently once all interview answers (see `interview-questions.md`)
are in hand. Never explain these technical choices to the project leader
unless they ask.

## Visual interface (Q4)

- "Yes" or "Not sure" → App type: web application. Tech: Next.js + Material
  UI (MUI), each at its current stable major — see PACKAGE VERSIONING in
  `scaffold-web-nextjs.md`, resolved caret ranges, never the literal string
  `"latest"`. Folder structure: `scaffold-web-nextjs.md`.
- "No — it runs automatically" → App type: background worker / scheduled
  job. Tech: Python / FastAPI (no version pins in requirements.txt). Folder
  structure: `scaffold-worker-python.md`.

## Users & auth (Q3, Q7, Q8)

- "Our team / staff only" → Auth: Ory Hydra OIDC (UAB single sign-on) — see
  `auth-hydra-oidc.md`. ALSO gate the entire app behind a full-screen login
  splash (AuthGate) — no page renders before sign-in. Any valid BlazerID
  sign-in gets access — the platform does not do per-user or per-group
  authorization within UAB.
- "Our customers" → Auth: None (or Ory Hydra OIDC if login was mentioned —
  but check EXTERNAL USERS below first).
- "Both" → Auth: Ory Hydra OIDC (check EXTERNAL USERS below first).
- "Not sure" → Auth: Ory Hydra OIDC (safer default).

**Precedence** (how Q3, Q7, and Q8 interact everywhere in this skill): Q7
(sensitivity override) > Q8 (explicit login answer) > Q3 (audience default).
Staff-only (Q3 = A) always gets the AuthGate whenever login exists, no matter
which rule turned login on.

**EXTERNAL USERS CAN'T USE BLAZERID — escalate instead of generating auth:**
Hydra/BlazerID is UAB single sign-on. Patients, the public, and partner
organizations have no BlazerID, so Hydra login is unusable for them. If the
audience includes non-UAB users (Q3 = B or C) AND login is needed (login was
mentioned, Q8 = A or B, or Q7 forced it on), OR if Q8 = B ("some other kind
of account") for ANY audience: **stop generation of the auth layer.** State
plainly in PLAN.md that login for outside users needs a decision from IT (out
of scope for automatic generation), continue generating everything else
normally, and stub auth — generate `src/auth/` with a clear TODO and no
wired-up provider, and leave AppShell's sign-in control out. Never silently
generate Hydra for users who cannot have BlazerIDs. This escalation outranks
even Q7's forced-login rule: Q7 still forces the compliance banner wording,
but the auth layer itself stays stubbed and flagged.

Every front-facing app that needs a login uses this same pattern — never
Microsoft Entra ID, MSAL, next-auth, or any other auth library. See
`auth-hydra-oidc.md` for exactly what to generate. Hydra login works locally
out of the box with real values (see `auth-hydra-oidc.md`) — registering a
client for wherever this app eventually gets deployed for real is a separate
step for whoever deploys it, documented in `readme-template.md`, not
something this skill provisions.

Only "Our team / staff only" gets the mandatory login gate. "Our customers",
"Both", and "Not sure" keep an optional sign-in/sign-out control in the nav
bar instead — those apps expect visitors who never sign in at all, so nothing
should block the homepage.

## Data sensitivity (Q7)

Answer A–E → set an internal `sensitiveData` flag for the rest of
generation, and:
- **Force auth on:** use Ory Hydra OIDC (`auth-hydra-oidc.md`) even if Q3 or
  an explicit "no login" at Q8 implied no login was needed. Note in PLAN.md
  that this was overridden and why — never silently drop the override.
  EXCEPTION: if the audience includes non-UAB users, the EXTERNAL USERS
  escalation above wins instead — auth is stubbed and flagged for IT, never
  Hydra-generated for users without BlazerIDs.
- PLAN.md gets a banner as its first line (see `interview-questions.md`).
  Map category → office:
  - Student records → the Privacy Office
  - Health info → the HIPAA Security/Privacy Officer
  - Payment/banking info → the payment compliance team
  - Research/export-controlled data → the IRB / export control office
  - SSNs or other personal ID numbers → the Privacy Office
- README.md gets a matching "Before You Go Live" section (see
  `readme-template.md`).

Answer F → proceed normally, no banner, no forced login.

Answer G → in the interview, ask the one follow-up in
`interview-questions.md` Q7 rather than guessing.

## Data storage (Q6 = A or C — saving NEW information)

This skill generates no cloud infrastructure, so data storage is always a
real, working LOCAL implementation — never a connection-string placeholder
or a `YOUR_..._HERE` value the project leader has to fill in. See
`data-layer.md` for exactly how. If this app is later deployed somewhere
permanent, swapping the local storage for a hosted database/storage account
is a follow-up step for whoever does that deployment — out of scope here.

- "Yes — structured / records / lists" → a local SQLite file
  (`./.data/local.db`). Generate ONE working sample entity (e.g. "items")
  with create + list and auto-create-schema-on-startup.
- "Yes — files / documents / uploads" → local file storage under
  `./.localstorage`.
- "Yes — not sure what kind" → generate BOTH; add a comment explaining which
  one to remove later.
- "No" or blank → no database dependency.

## Existing system integration (Q6 = B or C)

This is fundamentally different from DATA STORAGE — it connects to a system
that already exists elsewhere, so it can never be auto-provisioned. Say so
plainly to the project leader: IT needs to arrange access (an API key, a
service account, a connection string) before this integration works. That
credential is a real secret and belongs only in `.env.local` on whichever
machine runs the app — never committed to the zip, never pasted into a file
that ships with the source.

For each system named, using a short lowercase hyphenated `<system>` name:
- Generate a stub integration file with a clear TODO at
  `src/lib/integrations/<system>.ts` (Next.js) or
  `services/integrations/<system>.py` (Python worker). Server-side only —
  never a client component.
- Derive an env var name per credential (e.g. `BANNER_API_URL`,
  `BANNER_API_KEY` — never prefixed `NEXT_PUBLIC_`), read directly from the
  environment.
- Document the env var names (not values) in `.env.template` and add blank
  stub lines in `.env.local` for local testing (gitignored — see
  `data-layer.md`).
- List the system in PLAN.md under "Systems this app needs access to" and in
  README.md's setup steps as something to arrange access for and fill into
  `.env.local` (or wherever it's deployed) — never an instruction to edit a
  file inside the zip itself.

## AI usage (Q9)

- "Yes"/"Not sure" + chat/search/summarize-shaped → ask the shared-vs-own
  follow-up in `interview-questions.md` Q9.
  - "Shared assistant" → AI service stub reading a single endpoint from
    `AI_SHARED_ASSISTANT_ENDPOINT`, TODO for how this app calls it. Do not
    provision a separate API key.
  - "Own connection" or doesn't fit shared-assistant → proceed below.
- "Yes" → Add AI service stub (`lib/aiClient.ts` or `services/ai_service.py`)
  using the Anthropic Claude API. Read endpoint + key from env vars, TODO for
  prompt logic.
- "No" → no AI dependency.
- "Not sure" (and shared-assistant question didn't resolve it) → commented-out
  stub with a note.

## Lifecycle & governance (Q11)

Never shown back to the project leader as "technical" — flows silently into
README.md's "Who to contact" section as the point of contact for this
project.

## ALWAYS (regardless of answers)

- UAB brand theme, generated from the live brand guide (`branding-theme.md`).
- WCAG 2.1 AA accessibility, built into the generated theme.
- Dark mode + light mode respecting OS preference.
- Auto-wire every data store/integration chosen to a real local
  implementation — never ask the project leader for a connection string,
  key, or any technical value.
- This skill does NOT install, audit, build, run, or check the generated
  app in any way — no `npm install`/`npm audit`/`npm run build`, no dev
  server, no static checklist. See `SKILL.md` for why. Package it into a
  downloadable zip (`scripts/package-app-fast.sh`) as the final step, and
  always tell the project leader plainly that the code was generated but
  never installed, built, or checked — see `SKILL.md`'s report-back step
  for the exact wording.
