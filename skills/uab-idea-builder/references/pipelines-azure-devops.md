# Three Pipelines — azure-pipelines-dev.yml, -qa.yml, -prod.yml

UAB's Azure Repos convention (always follow this — it's the standardized
process, not a per-app choice) is three branches, each with its own
pipeline: `develop`, `qa`, and `production`. Development and Production each
get their own real, persistent Azure resources — completely separate
resource groups, databases, and storage, achieved for free by giving each
one a different `AZURE_ENV_NAME` (see `infra-bicep.md` — no changes needed
there, it already keys the resource group name off `environmentName`). QA
gets NO Azure resources at all: its pipeline exists purely to build and
smoke-test a pull request before it's allowed to reach production, reusing
the exact install/build/start/health-check steps
`scripts/verify-web-app.sh` / `verify-worker-app.sh` already define.

Generate all three files at the repo root.

## `azure-pipelines-dev.yml` — auto-deploy to Development on every push to `develop`

No approval gate — this is the fast inner loop, so a plain `job`, not a
`deployment`/`environment`.

```yaml
# ─────────────────────────────────────────────────────────────────────────
# SETUP REQUIRED (one time, done by your IT team — not the project leader):
#
# Create a Variable Group in ADO:
#   Project Settings → Pipelines → Library → + Variable Group
#   Name it: <app-name>-dev-variables
#   Add these variables (mark secrets as secret):
#     AZURE_SUBSCRIPTION_ID  — your Azure subscription ID
#     AZURE_TENANT_ID        — your Azure AD tenant ID
#     AZURE_CLIENT_ID        — service principal client ID   [SECRET]
#     AZURE_CLIENT_SECRET    — service principal secret      [SECRET]
#     AZURE_LOCATION         — Azure region (e.g. eastus2)
#     AZURE_ENV_NAME         — environment name (e.g. <app-name>-dev)
#   (Only if this app has a login) also add, with DEVELOPMENT values:
#     NEXT_PUBLIC_AUTH_URL     — https://<frontdoor-dev>/auth2/public/
#     NEXT_PUBLIC_CLIENT_ID    — the Hydra client ID registered for this app
#     NEXT_PUBLIC_REDIRECT_URL — the Development deployment's URL
#   These three are BUILD-TIME values, baked into the browser bundle when
#   the image is built (see azure.yaml's docker buildArgs) — setting them on
#   the deployed Container App does nothing.
#
# NOTE: AZURE_CLIENT_SECRET expires (tenant policy commonly caps client
# secrets at ≤24 months) — track the expiry date and rotate it before it
# lapses; an expired secret is the classic "pipeline broke a year later"
# failure. Better: prefer an ADO service connection with workload identity
# federation over a stored secret — azd supports `azd auth login
# --client-id ... --federated-credential-provider azure-pipelines` inside
# an AzureCLI@2 task.
#
# Grant the pipeline access to the variable group, then register this file
# as its own Pipeline in ADO (Pipelines → New pipeline → point it at
# azure-pipelines-dev.yml) so it only triggers off the `develop` branch.
# ─────────────────────────────────────────────────────────────────────────

trigger:
  batch: true   # queue runs instead of overlapping them — two quick pushes
                # must never run azd up concurrently against the same
                # resource group (that produces confusing ARM conflicts)
  branches:
    include:
      - develop

variables:
  - group: <app-name>-dev-variables

stages:
  - stage: DeployDev
    displayName: Deploy to Development
    jobs:
      - job: AzdUp
        displayName: Run azd up
        pool:
          vmImage: ubuntu-latest
        steps:
          - script: curl -fsSL https://aka.ms/install-azd.sh | bash
            displayName: Install Azure Developer CLI

          - script: |
              azd auth login \
                --client-id $(AZURE_CLIENT_ID) \
                --client-secret $(AZURE_CLIENT_SECRET) \
                --tenant-id $(AZURE_TENANT_ID)
            displayName: Authenticate with Azure
            env:
              AZURE_CLIENT_ID: $(AZURE_CLIENT_ID)
              AZURE_CLIENT_SECRET: $(AZURE_CLIENT_SECRET)
              AZURE_TENANT_ID: $(AZURE_TENANT_ID)

          - script: azd up --no-prompt
            displayName: Provision infrastructure and deploy app
            env:
              AZURE_SUBSCRIPTION_ID: $(AZURE_SUBSCRIPTION_ID)
              AZURE_TENANT_ID: $(AZURE_TENANT_ID)
              AZURE_ENV_NAME: $(AZURE_ENV_NAME)
              AZURE_LOCATION: $(AZURE_LOCATION)
              # Only if this app has a login — azd passes these through to
              # the Docker build args (see azure.yaml); remove otherwise:
              NEXT_PUBLIC_AUTH_URL: $(NEXT_PUBLIC_AUTH_URL)
              NEXT_PUBLIC_CLIENT_ID: $(NEXT_PUBLIC_CLIENT_ID)
              NEXT_PUBLIC_REDIRECT_URL: $(NEXT_PUBLIC_REDIRECT_URL)
```

## `azure-pipelines-qa.yml` — validate only, never deploys, no Azure credentials

This is a build/test gate, not a deployment. It reuses the same
install/build/serve/health-check logic as
`scripts/verify-web-app.sh` / `verify-worker-app.sh` so there is exactly one
place that defines "does this app actually work" — do not invent different
checks here. Unlike that local dev-server check, run the same production
build the Dockerfile runs (`npm run build` + `npm start`), since the point of
this gate is to catch anything that only breaks in a production-style run.

```yaml
# ─────────────────────────────────────────────────────────────────────────
# SETUP REQUIRED (one time, done by your IT team — not the project leader):
#
# No variable group needed — this pipeline never touches Azure.
# Register this file as its own Pipeline in ADO (Pipelines → New pipeline →
# point it at azure-pipelines-qa.yml), then add it as a required check on
# both the `qa` and `production` branches:
#   Repos → Branches → (branch) → Branch policies → Build Validation →
#   add this pipeline, mark it required.
# This is what makes it "test the pull request before it's allowed to merge."
# ─────────────────────────────────────────────────────────────────────────

trigger:
  branches:
    include:
      - qa

# NOTE: no `pr:` block here on purpose — Azure Repos ignores YAML `pr:`
# triggers entirely (only GitHub/Bitbucket honor them). PR validation for
# `qa` and `production` comes from the Build Validation branch policy
# described in the SETUP comment above; that policy is what actually runs
# this pipeline on pull requests.

pool:
  vmImage: ubuntu-latest

stages:
  - stage: ValidateQA
    displayName: Build and verify (no deployment)
    jobs:
      - job: InstallBuildVerify
        displayName: Install, build, and health-check
        steps:
          # Both app types: compile-check the infrastructure templates.
          # Syntax/compile only — needs no Azure credentials. Without this,
          # the prod pipeline would be the first thing to ever compile the
          # Bicep.
          - script: az bicep build --file infra/main.bicep
            displayName: Validate Bicep templates

          # Web app (Next.js):
          - script: npm ci
            displayName: Install dependencies
          - script: npm run build
            displayName: Build
          - script: npm test
            displayName: Run smoke tests
          - script: |
              npm start &
              sleep 10
              curl --fail http://localhost:3000/api/health
            displayName: Start app and check health endpoint

          # Worker (Python FastAPI) — use these steps instead of the npm
          # steps above when the app type is a background worker:
          # - script: pip install -r requirements.txt
          #   displayName: Install dependencies
          # - script: pytest
          #   displayName: Run smoke tests
          # - script: |
          #     uvicorn app.main:app --host 0.0.0.0 --port 8000 &
          #     sleep 5
          #     curl --fail http://localhost:8000/health
          #   displayName: Start app and check health endpoint
```

## `azure-pipelines-prod.yml` — approval-gated deploy to Production on push to `production`

The pipeline is idempotent — `azd` detects existing resources on subsequent
runs and only redeploys the container image. The deploy step targets an ADO
Environment, so it pauses for a manual approval before actually reaching
production (see LIFECYCLE & GOVERNANCE in `decision-matrix.md`) instead of
pushing straight to prod on every push with no checkpoint.

```yaml
# ─────────────────────────────────────────────────────────────────────────
# SETUP REQUIRED (one time, done by your IT team — not the project leader):
#
# Create a Variable Group in ADO:
#   Project Settings → Pipelines → Library → + Variable Group
#   Name it: <app-name>-prod-variables
#   Add these variables (mark secrets as secret):
#     AZURE_SUBSCRIPTION_ID  — your Azure subscription ID
#     AZURE_TENANT_ID        — your Azure AD tenant ID
#     AZURE_CLIENT_ID        — service principal client ID   [SECRET]
#     AZURE_CLIENT_SECRET    — service principal secret      [SECRET]
#     AZURE_LOCATION         — Azure region (e.g. eastus2)
#     AZURE_ENV_NAME         — environment name (e.g. <app-name>-prod)
#   (Only if this app has a login) also add, with PRODUCTION values:
#     NEXT_PUBLIC_AUTH_URL     — https://<frontdoor>/auth2/public/
#     NEXT_PUBLIC_CLIENT_ID    — the Hydra client ID registered for this app
#     NEXT_PUBLIC_REDIRECT_URL — the Production app URL
#   These three are BUILD-TIME values, baked into the browser bundle when
#   the image is built (see azure.yaml's docker buildArgs) — setting them on
#   the deployed Container App does nothing.
#
# NOTE: AZURE_CLIENT_SECRET expires (tenant policy commonly caps client
# secrets at ≤24 months) — track and rotate it, or prefer a service
# connection with workload identity federation (see the same note in
# azure-pipelines-dev.yml).
#
# Grant the pipeline access to the variable group, then register this file
# as its own Pipeline in ADO (Pipelines → New pipeline → point it at
# azure-pipelines-prod.yml) so it only triggers off the `production` branch.
#
# Create an Environment for the production approval gate:
#   Pipelines → Environments → New environment → name it "<app-name>-production"
#   Open it → ⋮ → Approvals and checks → Approvals → add the approver(s).
#   <<< If DATA SENSITIVITY (Q7) flagged this app, name the required office
#       here instead of a generic approver — e.g. "requires sign-off from
#       the Privacy Office" or "requires sign-off from the HIPAA Security
#       Officer" — see decision-matrix.md for the category → office map. >>>
# ─────────────────────────────────────────────────────────────────────────

trigger:
  branches:
    include:
      - production

variables:
  - group: <app-name>-prod-variables

stages:
  - stage: DeployProd
    displayName: Deploy to Production
    jobs:
      - deployment: AzdUp
        displayName: Run azd up
        pool:
          vmImage: ubuntu-latest
        environment: '<app-name>-production'
        strategy:
          runOnce:
            deploy:
              steps:
                # REQUIRED FIRST STEP: deployment jobs do NOT check out the
                # repo automatically (unlike a plain `job`) — without this,
                # azd up runs in an empty workspace, finds no azure.yaml,
                # and fails.
                - checkout: self

                - script: curl -fsSL https://aka.ms/install-azd.sh | bash
                  displayName: Install Azure Developer CLI

                - script: |
                    azd auth login \
                      --client-id $(AZURE_CLIENT_ID) \
                      --client-secret $(AZURE_CLIENT_SECRET) \
                      --tenant-id $(AZURE_TENANT_ID)
                  displayName: Authenticate with Azure
                  env:
                    AZURE_CLIENT_ID: $(AZURE_CLIENT_ID)
                    AZURE_CLIENT_SECRET: $(AZURE_CLIENT_SECRET)
                    AZURE_TENANT_ID: $(AZURE_TENANT_ID)

                - script: azd up --no-prompt
                  displayName: Provision infrastructure and deploy app
                  env:
                    AZURE_SUBSCRIPTION_ID: $(AZURE_SUBSCRIPTION_ID)
                    AZURE_TENANT_ID: $(AZURE_TENANT_ID)
                    AZURE_ENV_NAME: $(AZURE_ENV_NAME)
                    AZURE_LOCATION: $(AZURE_LOCATION)
                    # Only if this app has a login — azd passes these
                    # through to the Docker build args (see azure.yaml);
                    # remove otherwise:
                    NEXT_PUBLIC_AUTH_URL: $(NEXT_PUBLIC_AUTH_URL)
                    NEXT_PUBLIC_CLIENT_ID: $(NEXT_PUBLIC_CLIENT_ID)
                    NEXT_PUBLIC_REDIRECT_URL: $(NEXT_PUBLIC_REDIRECT_URL)

# NOTE: unlike a plain `job`, a `deployment` job SKIPS automatic source
# checkout by design — that is why the explicit `- checkout: self` above is
# the first step and is required. Versus a plain `job`, the changes are:
# `environment:`, the runOnce/deploy wrapper, and that checkout step.
```
