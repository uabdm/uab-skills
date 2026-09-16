# `.env.template`

List every environment variable the scaffold references, in these sections:

```
# ── App ──────────────────────────────────────────────────────────────────
APP_NAME=<app-name>
APP_ENV=development
PORT=3000   # or 8000 for Python

# ── Azure Key Vault ───────────────────────────────────────────────────────
# URI format: https://<vault-name>.vault.azure.net/
# Your IT team will create this Key Vault during deployment.
AZURE_KEY_VAULT_URI=https://YOUR_KEY_VAULT_NAME.vault.azure.net/

# ── Authentication (Ory Hydra OIDC, if login is needed) ────────────────────
# IMPORTANT: these three are BUILD-TIME values. Next.js bakes NEXT_PUBLIC_*
# into the browser bundle when the Docker image is built on the pipeline
# agent — setting them on the deployed Container App at runtime does
# NOTHING. IT sets them as pipeline variable-group values (dev values in
# <app-name>-dev-variables, prod values in <app-name>-prod-variables — see
# the SETUP comments in the pipeline files); they flow into the image via
# docker build args (see pipelines-azure-devops.md / azure-yaml.md).
# authority: UAB's identity server. clientId: the Hydra client ID your IT
# team registers for this app (matches the app's lowercase-hyphenated name).
# redirectUrl: that environment's app URL. Locally, .env.local already has
# working values — see auth-hydra-oidc.md — so nothing to fill in here.
NEXT_PUBLIC_AUTH_URL=YOUR_HYDRA_AUTHORITY_URL
NEXT_PUBLIC_CLIENT_ID=YOUR_HYDRA_CLIENT_ID
NEXT_PUBLIC_REDIRECT_URL=YOUR_APP_URL

# ── AI Model (if AI is used, own connection) ────────────────────────────
# Your IT team will provide the endpoint and key for the AI service.
AI_MODEL_ENDPOINT=https://YOUR_ENDPOINT_HERE
AI_MODEL_API_KEY=YOUR_API_KEY_HERE

# ── AI Model (if AI is used, shared university assistant instead) ───────
# Your IT team will provide this if this app was set up to use the
# university's shared AI assistant instead of its own connection.
AI_SHARED_ASSISTANT_ENDPOINT=https://YOUR_SHARED_ASSISTANT_ENDPOINT_HERE

# ── External systems (one block per system named in Q6, if any) ──────────
# <system name> — managed automatically. Your IT team sets the real value
# directly in Key Vault once access is arranged (see README's Key Vault
# setup step) — do NOT fill this in here or anywhere in this repo. For
# local testing, put a real dev/test value in .env.local instead (that
# file is gitignored and never committed).
# <SYSTEM>_API_URL=
# <SYSTEM>_API_KEY=

# ── Database (managed automatically — do NOT fill this in) ────────────────
# Leave this blank. On your computer the app uses a local file automatically.
# In Azure this is filled in for you from Key Vault when the app deploys.
# DATABASE_URL=

# ── File storage (managed automatically — do NOT fill this in) ────────────
# Leave this blank. On your computer files are saved to ./.localstorage
# automatically. In Azure this is filled in for you from Key Vault on deploy.
# AZURE_STORAGE_CONNECTION_STRING=
```

Include only the variables actually used. Never put real values in this file
— not even for local development; local values belong in `.env.local` (see
`auth-hydra-oidc.md` and `decision-matrix.md`), which is gitignored and never
committed. Add a plain-English comment above each variable explaining where
to get it. For values that are provisioned and injected automatically
(database, storage, external-system connections), leave them commented
out/blank and say so in the comment — the project leader must never have to
find or paste a connection string, and IT must never be told to paste a real
secret here.
