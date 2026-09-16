# `.env.template`

List every environment variable the scaffold references, in these sections:

```
# ── App ──────────────────────────────────────────────────────────────────
APP_NAME=<app-name>
APP_ENV=development
PORT=3000   # or 8000 for Python

# ── Authentication (Ory Hydra OIDC, if login is needed) ────────────────────
# Locally, .env.local already has real, working values — see
# auth-hydra-oidc.md — so nothing to fill in here for local development.
# If this app is later deployed somewhere permanent, whoever deploys it
# needs to register a client with UAB's Ory Hydra server for that
# deployment's URL and set these three there. authority: UAB's identity
# server. clientId: the Hydra client ID registered for this app. redirectUrl:
# that deployment's app URL.
NEXT_PUBLIC_AUTH_URL=YOUR_HYDRA_AUTHORITY_URL
NEXT_PUBLIC_CLIENT_ID=YOUR_HYDRA_CLIENT_ID
NEXT_PUBLIC_REDIRECT_URL=YOUR_APP_URL

# ── AI Model (if AI is used, own connection) ────────────────────────────
# Provide your own endpoint and key for the AI service.
AI_MODEL_ENDPOINT=https://YOUR_ENDPOINT_HERE
AI_MODEL_API_KEY=YOUR_API_KEY_HERE

# ── AI Model (if AI is used, shared university assistant instead) ───────
# Fill this in if this app was set up to use the university's shared AI
# assistant instead of its own connection.
AI_SHARED_ASSISTANT_ENDPOINT=https://YOUR_SHARED_ASSISTANT_ENDPOINT_HERE

# ── External systems (one block per system named in Q6, if any) ──────────
# <system name> — arrange access with the system owner, then put the real
# value directly in .env.local (gitignored, never committed, never shipped
# in the handoff zip) — do NOT fill this in here or anywhere else in this
# project.
# <SYSTEM>_API_URL=
# <SYSTEM>_API_KEY=

# ── Data storage (works automatically — nothing to fill in) ───────────────
# This app saves data to a local file (see data-layer.md) — no
# configuration needed, locally or wherever it's later deployed.
```

Include only the variables actually used. Never put real values in this file
— not even for local development; local values belong in `.env.local` (see
`auth-hydra-oidc.md` and `decision-matrix.md`), which is gitignored and never
committed. Add a plain-English comment above each variable explaining where
to get it. The project leader must never have to find or paste a connection
string or technical value anywhere in this file.
