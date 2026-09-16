# `azure.yaml`

Write to the repo root. This file tells the Azure Developer CLI how to build
and deploy the app.

```yaml
name: <app-name>
services:
  app:
    project: .
    language: js    # use 'py' for Python workers
    host: containerapp
    docker:
      # ALWAYS set remoteBuild: true, for EVERY app (login or not). This tells
      # azd to build the container image with an ACR Task in Azure instead of
      # shelling out to a local Docker daemon — so `azd deploy`/`azd up`
      # need no Docker install at all, whether run from a developer laptop or
      # an ADO pipeline agent. It is a permanent, safe setting, not a
      # local-machine workaround, and it is why .dockerignore matters (see
      # data-layer.md — azd tars and uploads the build context).
      remoteBuild: true
      # buildArgs ONLY when login was chosen: Next.js inlines NEXT_PUBLIC_*
      # values into the browser bundle at build time, so they must reach the
      # Docker build as build args — values come from the pipeline variable
      # groups via the azd up step's env block (see pipelines-azure-devops.md).
      # Omit just the buildArgs list (NOT the docker: block or remoteBuild)
      # if the app has no login.
      buildArgs:
        - NEXT_PUBLIC_AUTH_URL=${NEXT_PUBLIC_AUTH_URL}
        - NEXT_PUBLIC_CLIENT_ID=${NEXT_PUBLIC_CLIENT_ID}
        - NEXT_PUBLIC_REDIRECT_URL=${NEXT_PUBLIC_REDIRECT_URL}
infra:
  provider: bicep
```
