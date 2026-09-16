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
even Q7's forced-login rule: Q7 still forces the compliance banner and
approval-gate wording, but the auth layer itself stays stubbed and flagged.

Every front-facing app that needs a login uses this same pattern — never
Microsoft Entra ID, MSAL, next-auth, or any other auth library. See
`auth-hydra-oidc.md` for exactly what to generate.

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
- `azure-pipelines-prod.yml`'s production approval gate must name the
  required approving office in its description, not just "an approver" (see
  `pipelines-azure-devops.md`).

Answer F → proceed normally, no banner, no forced login.

Answer G → in the interview, ask the one follow-up in
`interview-questions.md` Q7 rather than guessing.

## Data storage (Q6 = A or C — saving NEW information)

Whatever is chosen MUST be provisioned in Bicep AND wired into the running
app automatically. Never emit a connection-string TODO or a `YOUR_..._HERE`
placeholder the project leader has to fill in. The rule: works locally with
zero configuration, works in Azure with zero configuration. See
`data-layer.md` for how.

- "Yes — structured / records / lists" → Azure SQL. Bicep provisions a SQL
  server + database; connection string written to Key Vault at deploy time;
  Container App reads it as `DATABASE_URL` via a Key Vault reference. Local:
  falls back to a SQLite file automatically. Generate ONE working sample
  entity (e.g. "items") with create + list and auto-create-schema-on-startup.
- "Yes — files / documents / uploads" → Azure Blob Storage. Bicep provisions
  a storage account + container; connection string in Key Vault, injected as
  `AZURE_STORAGE_CONNECTION_STRING`. Local: falls back to `./.localstorage`.
- "Yes — not sure what kind" → provision and wire BOTH; add a comment
  explaining which one to remove later.
- "No" or blank → no database dependency.

## Existing system integration (Q6 = B or C)

This is fundamentally different from DATA STORAGE — it is NOT
auto-provisionable. Say so plainly to the project leader: IT needs to arrange
access (an API key, a service account, a connection string) before this
integration works. Once IT has the credential, it goes directly into Azure
Key Vault — never pasted into a file in this repo.

For each system named, using a short lowercase hyphenated `<system>` name:
- Generate a stub integration file with a clear TODO at
  `src/lib/integrations/<system>.ts` (Next.js) or
  `services/integrations/<system>.py` (Python worker). Server-side only —
  never a client component.
- Derive a Key Vault secret name per credential (e.g. `banner-api-url`,
  `banner-api-key`) and the matching env var (`BANNER_API_URL`,
  `BANNER_API_KEY` — never prefixed `NEXT_PUBLIC_`). `infra/main.bicep`
  provisions a placeholder secret for each at deploy time so the Container
  App's `secretRef` always resolves before IT has the real value.
- Document the env var names (not values) in `.env.template` and add blank
  stub lines in `.env.local` for local testing (gitignored — see
  `data-layer.md`).
- List the system in PLAN.md under "Systems this app needs access to" and in
  README.md's IT setup steps with the exact Key Vault secret-setting
  instructions (see `readme-template.md`) — never an instruction to edit a
  file in this repo.

## AI usage (Q9)

- "Yes"/"Not sure" + chat/search/summarize-shaped → ask the shared-vs-own
  follow-up in `interview-questions.md` Q9.
  - "Shared assistant" → AI service stub reading a single endpoint from
    `AI_SHARED_ASSISTANT_ENDPOINT`, TODO for how this app calls it. Do not
    provision a separate API key.
  - "Own connection" or doesn't fit shared-assistant → proceed below.
- "Yes" → Add AI service stub (`lib/aiClient.ts` or `services/ai_service.py`)
  using the Anthropic Claude API via Azure AI services. Read endpoint + key
  from env vars, TODO for prompt logic.
- "No" → no AI dependency.
- "Not sure" (and shared-assistant question didn't resolve it) → commented-out
  stub with a note.

## Lifecycle & governance (Q11)

Never shown back to the project leader as "technical" — flows into generated
files silently:
- `infra/main.bicep`: extend `tags` with `owner` (contact) and `costCenter`
  (department). Every module already receives `tags`.
- `infra/modules/monitor.bicep`: availability alert on the health endpoint,
  action group emails the Q11 contact.
- `azure-pipelines-prod.yml`: manual approval gate before production. If Q7
  flagged the app, name the required approving office in the environment's
  description.
- README.md: "Decommissioning This App" section — `azd down --purge` tears
  down every resource.

## ALWAYS (regardless of answers)

- Azure Key Vault for all secrets.
- Azure Container Apps as the deployment target.
- UAB brand theme, generated from the live brand guide (`branding-theme.md`).
- WCAG 2.1 AA accessibility, built into the generated theme.
- Dark mode + light mode respecting OS preference.
- `azure.yaml` + `infra/` Bicep templates (`azure-yaml.md`, `infra-bicep.md`).
- All three pipelines — dev, qa, prod — never a single pipeline
  (`pipelines-azure-devops.md`).
- Auto-provision AND auto-wire every data store/integration chosen — never
  ask the project leader for a connection string, key, or any technical
  value.
- Application Insights + Log Analytics, always provisioned, wired as
  `APPLICATIONINSIGHTS_CONNECTION_STRING`. Be honest in README: Container
  Apps has no codeless instrumentation and the scaffold ships no App
  Insights SDK, so only the availability test reports — in-app telemetry
  needs the SDK added later. Generate a TODO stub
  (`src/lib/appInsights.ts` / `app/services/app_insights.py`) noting this.
- Container App scaling, decided silently from Q3, never asked: "Our team /
  staff only" → `minReplicas: 0` (scale-to-zero; low-traffic, bursty, cost
  matters more than an occasional cold start). Any other answer →
  `minReplicas: 1` (a public app's first visitor shouldn't hit a cold
  start). `maxReplicas` stays 3 for both.
- When Blob Storage is provisioned, turn on blob soft-delete and versioning.
  Azure SQL already has automatic point-in-time backup — just say so in
  README, add nothing to Bicep for it.
- Run the verification loop (`verification-checklist.md` +
  `scripts/verify-web-app.sh` / `verify-worker-app.sh`) after generating
  everything. Never tell the project leader the app is ready until it
  installs, builds, starts, and serves with zero errors.
