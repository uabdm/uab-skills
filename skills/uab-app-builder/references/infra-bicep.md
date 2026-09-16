# Infrastructure — `infra/` Bicep templates

Generate Bicep templates that provision a complete Azure environment from
scratch. The `azd` CLI reads these templates and creates all resources.

**Contents:** main.bicep · main.parameters.json · abbreviations.json ·
modules/identity.bicep · modules/registry.bicep · modules/keyvault.bicep ·
modules/appinsights.bicep · modules/monitor.bicep (webtest schema traps) ·
modules/sql.bicep · modules/storage.bicep · modules/containerapp.bicep

## `infra/main.bicep`

```bicep
targetScope = 'subscription'

@minLength(1)
@maxLength(64)
param environmentName string

@minLength(1)
// Default region for the AUTO/pipeline path. NOTE: some subscriptions block
// Azure SQL server creation in eastus/eastus2 (seen on a Visual Studio
// Enterprise subscription — "your subscription does not have access to
// create a server in the selected region"). If a deploy fails on the SQL
// server for that reason, override per-environment with
// `azd env set AZURE_LOCATION centralus` (this does not change the default
// here). The MANUAL deploy runbook uses centralus as its standard region.
param location string = 'eastus2'

// OIDC public config — declared here so main.parameters.json can inject the
// azd env values (see below) and main.bicep can forward them to the
// containerApps module. DEFAULT EACH TO '' — this is required, not optional:
// NEXT_PUBLIC_REDIRECT_URL is not knowable until AFTER the first
// `azd provision` creates the Container App and returns its URL, so on that
// first provision these have no value yet. Without a default, azd stops on
// an interactive prompt ("Enter a value for the 'authUrl' infrastructure
// parameter:") and FAILS OUTRIGHT under `azd up --no-prompt`, which BOTH
// pipelines use — so a missing default silently breaks the entire automated
// deploy path. Defaulting to '' lets the first provision succeed with blank
// OIDC config; the real values are set later (azd env set) and a re-provision
// (`azd up`) writes them in. Declare all three even if only some are used.
// Omit this whole block ONLY if the app has no login at all.
param authUrl string = ''
param clientId string = ''
param redirectUrl string = ''

var tags = { 'azd-env-name': environmentName, 'app': '<app-name>', 'owner': '<Q11 contact name/email>', 'costCenter': '<Q11 department/cost center>' }
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var abbrs = loadJsonContent('./abbreviations.json')

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// Created FIRST — before registry, keyVault, and containerApps — so its
// principalId is known up front and the AcrPull + Key Vault Secrets User
// role assignments can be granted BEFORE the Container App that depends on
// them exists. See identity.bicep for why this is user-assigned, not
// system-assigned, and the containerapp.bicep spec below for the deadlock
// this avoids.
module appIdentity './modules/identity.bicep' = {
  name: 'appIdentity'
  scope: rg
  params: {
    name: '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
    location: location
    tags: tags
  }
}

module registry './modules/registry.bicep' = {
  name: 'registry'
  scope: rg
  params: {
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
    location: location
    tags: tags
    // Grant the app identity AcrPull HERE, so it exists before the
    // Container App tries to pull its image.
    acrPullPrincipalId: appIdentity.outputs.principalId
  }
}

module appInsights './modules/appinsights.bicep' = {
  name: 'appInsights'
  scope: rg
  params: {
    name: '${abbrs.insightsComponents}${resourceToken}'
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    location: location
    tags: tags
  }
}

// DATA MODULES — include ONLY the ones the answers call for (see
// decision-matrix.md DATA STORAGE). Provision the data store first, then
// pass its connection string to Key Vault so it is stored as a secret, then
// expose it to the Container App.
//
// module sql './modules/sql.bicep' = if (needsSql) {        // structured data
//   name: 'sql'
//   scope: rg
//   params: {
//     serverName: '${abbrs.sqlServers}${resourceToken}'
//     databaseName: 'appdb'
//     administratorPassword: sqlAdminPassword   // @secure() param, see below
//     location: location
//     tags: tags
//   }
// }
// module storage './modules/storage.bicep' = if (needsStorage) {  // file/uploads
//   name: 'storage'
//   scope: rg
//   params: {
//     name: '${abbrs.storageStorageAccounts}${resourceToken}'
//     location: location
//     tags: tags
//   }
// }

// EXTERNAL INTEGRATION SECRETS — one placeholder per credential named under
// EXISTING SYSTEM INTEGRATION in decision-matrix.md (e.g. 'banner-api-url',
// 'banner-api-key'). These are NOT auto-provisioned like the data stores
// above — the real value is unknown at generation time, since it comes from
// an external system owner. Bicep only creates a placeholder so the
// Container App's secretRef resolves and the app deploys successfully from
// day one; IT overwrites the real value directly in Key Vault once access
// is arranged (see readme-template.md). Re-running a full infra provision
// resets it back to the placeholder — same caution as the SQL admin
// password note further below — so treat "set the Key Vault secret" as a
// step IT redoes after any full infra redeploy, not a one-time step.
// var externalIntegrationSecrets = [
//   { name: 'banner-api-url', envVar: 'BANNER_API_URL' }
//   { name: 'banner-api-key', envVar: 'BANNER_API_KEY' }
// ]

module keyVault './modules/keyvault.bicep' = {
  name: 'keyVault'
  scope: rg
  params: {
    name: '${abbrs.keyVaultVaults}${resourceToken}'
    location: location
    tags: tags
    // Grant the app identity Key Vault Secrets User HERE, so it exists
    // before the Container App tries to resolve its secret references.
    vaultUserPrincipalId: appIdentity.outputs.principalId
    // Pass any connection strings that were provisioned so the Key Vault
    // module stores them as secrets (e.g. 'database-url', 'storage-connection').
    // databaseConnectionString: needsSql ? sql.outputs.connectionString : ''
    // storageConnectionString:  needsStorage ? storage.outputs.connectionString : ''
    // Pass the external integration secret names so the module creates a
    // placeholder for each (see EXTERNAL INTEGRATION SECRETS above).
    // externalSecretNames: [for s in externalIntegrationSecrets: s.name]
  }
}

module containerApps './modules/containerapp.bicep' = {
  name: 'containerApps'
  scope: rg
  params: {
    // Named like every other resource — never environmentName directly:
    // Container App names must be ≤32 chars, lowercase alphanumeric or
    // hyphens, starting with a letter, and AZURE_ENV_NAME isn't
    // constrained to any of that. Display identity comes from the tags.
    appName: '${abbrs.appContainerApps}${resourceToken}'
    location: location
    tags: tags
    containerRegistryLoginServer: registry.outputs.loginServer
    keyVaultName: keyVault.outputs.name
    appInsightsConnectionString: appInsights.outputs.connectionString
    logAnalyticsWorkspaceId: appInsights.outputs.logAnalyticsWorkspaceId
    // The pre-created user-assigned identity — it ALREADY holds AcrPull (on
    // the registry) and Key Vault Secrets User (on the vault) by the time
    // this module runs, because those assignments live in the registry and
    // keyVault modules above. The Container App uses it to pull its image
    // and to resolve its Key Vault secret references (DATABASE_URL,
    // AZURE_STORAGE_CONNECTION_STRING) with zero config.
    userAssignedIdentityId: appIdentity.outputs.id
    // minReplicas/maxReplicas: see the ALWAYS list in decision-matrix.md —
    // 0/3 for "Our team / staff only" (Q3), 1/3 otherwise.
    // OIDC public config — pass these ONLY when login was chosen. They are
    // ALSO build args (azure-yaml.md) for the browser bundle, but the server-side
    // token verifier reads them at runtime, so they must reach the Container
    // App runtime env too (see the Dockerfile comment and containerapp.bicep).
    // Forwarded from the ''-defaulted authUrl/clientId/redirectUrl params
    // declared at the top of main.bicep, which main.parameters.json fills
    // from the azd env values. The '' defaults are what let the FIRST
    // provision succeed before the redirect URL exists (see those params).
    // authUrl:      authUrl       // NEXT_PUBLIC_AUTH_URL
    // clientId:     clientId      // NEXT_PUBLIC_CLIENT_ID
    // redirectUrl:  redirectUrl   // NEXT_PUBLIC_REDIRECT_URL
    // databaseSecretUri: needsSql ? keyVault.outputs.databaseSecretUri : ''
    // storageSecretUri:  needsStorage ? keyVault.outputs.storageSecretUri : ''
    // Same mechanism for external integrations — one secretUri per entry in
    // externalIntegrationSecrets above, mapped to its envVar.
    // externalSecretUris: keyVault.outputs.externalSecretUris
  }
}

module monitor './modules/monitor.bicep' = {
  name: 'monitor'
  scope: rg
  params: {
    name: '${abbrs.insightsActionGroups}${resourceToken}'
    location: location
    tags: tags
    appInsightsId: appInsights.outputs.id
    appUri: containerApps.outputs.uri
    healthCheckPath: '/api/health'   // '/health' for the Python worker layout
    alertEmail: '<Q11 contact name/email>'
  }
}

// SQL admin password: generate it here — never ask the user. For example
// declare a @secure() param defaulted from a deploy-time value, or generate
// with newGuid() in a param default, so it is set automatically each deploy.
// NOTE: newGuid() as a param default generates a NEW password on every
// deploy. That stays self-consistent (the server password and the Key
// Vault secret update in the same run), but it silently invalidates any
// COPIED connection string — which is why README and the .env.local
// comments must say "re-copy DATABASE_URL from Key Vault after each
// deployment" (see data-layer.md and readme-template.md).

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.loginServer
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
output SERVICE_APP_URI string = containerApps.outputs.uri
```

## `infra/main.parameters.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "environmentName": { "value": "${AZURE_ENV_NAME}" },
    "location":        { "value": "${AZURE_LOCATION}" }
  }
}
```

WHEN LOGIN WAS CHOSEN, also map the OIDC public config so azd injects the env
values into matching bicep params (declared with `''` defaults in
`main.bicep` and forwarded to the containerApps module — see above). This is
what puts them on the Container App RUNTIME env, which the server-side token
verifier needs; the `azure.yaml` buildArgs only cover the build-time browser
inline. Add these entries alongside the two above:

```json
"authUrl":     { "value": "${NEXT_PUBLIC_AUTH_URL}" },
"clientId":    { "value": "${NEXT_PUBLIC_CLIENT_ID}" },
"redirectUrl": { "value": "${NEXT_PUBLIC_REDIRECT_URL}" }
```

On the FIRST provision these azd env values are unset, so azd passes empty
strings and the params fall back to their `''` defaults — which is exactly
why those defaults are mandatory (a `--no-prompt` pipeline provision would
otherwise fail). After the app URL is known, `azd env set NEXT_PUBLIC_*` and
a re-provision (`azd up`) write the real values in.

## `infra/abbreviations.json`

Standard azd abbreviations file mapping resource types to short prefixes.
Include at minimum:

```json
{
  "resourcesResourceGroups": "rg-",
  "containerRegistryRegistries": "cr",
  "keyVaultVaults": "kv-",
  "appContainerApps": "ca-",
  "appManagedEnvironments": "cae-",
  "sqlServers": "sql-",
  "sqlServersDatabases": "sqldb-",
  "storageStorageAccounts": "st",
  "insightsComponents": "appi-",
  "operationalInsightsWorkspaces": "log-",
  "insightsActionGroups": "ag-",
  "managedIdentityUserAssignedIdentities": "id-"
}
```

## `infra/modules/identity.bicep` (always)

Provisions a user-assigned managed identity
(`Microsoft.ManagedIdentity/userAssignedIdentities`) for the Container App.
Outputs: `id`, `principalId`, `clientId`, `name`.

**Why user-assigned and not system-assigned — this is load-bearing, do not
"simplify" it back to a system-assigned identity:** the Container App
resolves a Key Vault secret reference (`DATABASE_URL`, etc.) AT CREATION TIME
and pulls its image via AcrPull, so it must already hold both roles the
moment it is created. A system-assigned identity does not exist until the
app itself exists, so its role assignments can only be created afterwards —
which deadlocks: the app can't produce a healthy revision without the
secret, the secret can't be read without the role, and the role can't be
created until the app exists. ARM never breaks out of this and the deploy
fails with `ContainerAppOperationError: Operation expired` after ~10 minutes
— in the pipeline exactly as in a manual `azd up`. Creating the identity as
its own resource FIRST makes its principalId known up front, so
`registry.bicep` and `keyvault.bicep` (below) grant both roles before the
Container App is created.

## `infra/modules/registry.bicep`

Provisions an Azure Container Registry (Basic SKU — sufficient for this
scaffold; this design provisions one registry per app per environment, so a
bigger SKU just doubles cost for nothing). Admin user enabled for azd image
push; it can be disabled later if azd's push path authenticates via the
service principal instead — verify which during the first end-to-end dry
run. The Container App PULLS via the pre-created user-assigned identity +
AcrPull, not the admin user (see identity.bicep and containerapp.bicep).
Accepts an optional `acrPullPrincipalId` param (the app identity's
principalId, passed from main.bicep) and, when set, creates the AcrPull role
assignment scoped to the registry HERE — so the pull permission exists
before the Container App is created. Outputs: `name`, `loginServer`.

## `infra/modules/keyvault.bicep`

Provisions an Azure Key Vault (standard SKU, RBAC authorization enabled).
Accepts optional connection-string params and, when provided, writes them as
secrets (e.g. `database-url`, `storage-connection`). Accepts an optional
principal-id param (the app identity's principalId, passed from main.bicep)
and, when set, creates the "Key Vault Secrets User" role assignment scoped
to the vault HERE — so the app identity can read its secret references
before the Container App is created (see identity.bicep for the deadlock
this avoids). Name this param so it does NOT end in a secret-like word (e.g.
`vaultUserPrincipalId`, not `secretsUserPrincipalId`) — Bicep's
secure-secrets-in-params linter flags any param whose name looks like a
secret and emits a spurious warning otherwise.

Also accepts an optional list of external-integration secret names (see
EXTERNAL INTEGRATION SECRETS above) and creates a placeholder secret for
each — this is what lets the Container App's secretRef resolve before IT has
arranged real access to that system.

Outputs: `name`, `endpoint`, the secret URIs for any data-store secrets it
created (`databaseSecretUri`, `storageSecretUri`), and the secret URIs for
any external-integration placeholders it created (`externalSecretUris`).

## `infra/modules/appinsights.bicep`

Provisions a Log Analytics workspace and an Application Insights component
(workspace-based) pointed at it. Always included — see the ALWAYS list in
`decision-matrix.md`. Outputs: `connectionString`, `id` (the App Insights
resource id — monitor.bicep needs it for the webtest hidden-link tag and
alert scoping), `logAnalyticsWorkspaceId` (containerapp.bicep wires the
Container Apps Environment's logs to it).

## `infra/modules/monitor.bicep`

Always included — this is what makes an outage visible to someone instead of
silent. There is no simple "ping a URL" alert resource in Azure — do not
invent one; the real shape is this trio:

1. **An Application Insights standard availability test**
   (`Microsoft.Insights/webtests`, kind `'standard'`): request URL = the
   Container App URI + health check path (both passed in from main.bicep), a
   list of test locations (e.g. five standard Azure regions), frequency
   300s, and — REQUIRED for the portal/alerting linkage — the hidden-link
   tag referencing the App Insights component:
   `tags: union(tags, { 'hidden-link:${appInsightsId}': 'Resource' })`

   **SCHEMA TRAP:** a kind `'standard'` test MUST use the structured
   properties `Request` (with `RequestUrl`) and `ValidationRules` (e.g.
   `ExpectedHttpStatusCode: 200`, `SSLCheck`), NOT the legacy XML
   `Configuration.WebTest` blob. The XML-only `Configuration` shape is for
   kind `'ping'` tests; supplying it on a `'standard'` test fails deployment
   with `Value cannot be null. Parameter name: format` on the webtest
   resource. (The metric alert then never runs because it depends on the
   webtest.) Generate the structured `Request`/`ValidationRules` form.

2. **A metric alert** (`Microsoft.Insights/metricAlerts`) using criteria
   type `Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria` — a
   dedicated criteria type built specifically for a webtest-backed
   availability alert, not something to assemble from the general
   metric-alert criteria shape. Generate exactly:
   ```bicep
   scopes: [ webTest.id, appInsightsId ]
   criteria: {
     'odata.type': 'Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria'
     webTestId: webTest.id
     componentId: appInsightsId
     failedLocationCount: 2
   }
   tags: union(tags, { 'hidden-link:${appInsightsId}': 'Resource',
   'hidden-link:${webTest.id}': 'Resource' })
   ```

   **SCHEMA TRAP:** `Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria`
   is a DIFFERENT, also-valid `odata.type` on this same resource, and looks
   like the natural fit — `webTestId`/`componentId`/`failedLocationCount`
   read like metric-criteria fields, and that type's name
   ("SingleResource...") sounds right for "one webtest, one alert." It is
   the wrong type here and fails in two separate stages, each looking like a
   different bug:
   - (a) `scopes` must contain exactly ONE resource for
     `SingleResourceMultipleMetricCriteria`. Passing both `webTest.id` and
     `appInsightsId` (the correct scoping for the RIGHT criteria type, wrong
     for this one) deploys module-by-module far enough to reach this
     resource, then fails with `BadRequest: Scopes property is invalid.
     Only single resource is allowed for criteria type
     SingleResourceMultipleMetricCriteria.`
   - (b) Even after narrowing `scopes` to a single resource,
     `SingleResourceMultipleMetricCriteria` still needs a list of metric
     conditions under the property `allOf` — NOT `criteria`, despite the
     outer object (`properties.criteria`) already being named `criteria`.
     Naming the inner list `criteria` compiles and deploys with no error or
     warning, silently producing an EMPTY conditions list, and fails only
     when the alert rule itself is evaluated: `BadRequest: The criteria
     array must contain at least 1 condition.`

   `WebtestLocationAvailabilityCriteria` has neither trap: no `allOf` to
   misname, and `scopes` is supposed to hold both resources. This is
   Microsoft's own documented pattern for exactly this scenario — see the
   "Metric alert rule for an availability test" quickstart
   (`Azure/azure-quickstart-templates`,
   `quickstarts/microsoft.insights/monitoring-webtest-metric-alert`) —
   reproduce that shape rather than reasoning one out from the general
   MetricAlertCriteria docs.

3. **An action group** (`Microsoft.Insights/actionGroups`) with an email
   receiver = the Q11 contact.

Params: `appInsightsId` (App Insights resource id), `appUri` (the Container
App's URI), `healthCheckPath`, `alertEmail` — see the monitor module wiring
in main.bicep above.

## `infra/modules/sql.bicep` (only when structured storage was chosen)

Provisions an Azure SQL logical server + database (Basic/serverless tier is
fine for a POC). Takes a `@secure()` `administratorPassword` param. Adds a
firewall rule allowing Azure services so the Container App can connect — the
range `0.0.0.0`–`0.0.0.0` (Azure's documented special case meaning "allow
Azure services"). **NAME THIS RULE `AllowAzureServices`** — do NOT use the
historically common name `AllowAllWindowsAzureIps`: Azure REJECTS resource
names containing reserved words, and "Windows" is one, so that name fails
provisioning with a "Reserved resource name" error. This applies to any
resource name in the template, not just this rule — avoid reserved words.

Output: `connectionString` (a ready-to-use `DATABASE_URL` value). It MUST be
in ADO.NET format so `mssql@12` can parse it (see `data-layer.md` — the
driver has no `mssql://` URI parser):

```
'Server=tcp:${fqdn},1433;Initial Catalog=${databaseName};User ID=${administratorLogin};Password=${administratorPassword};Encrypt=true'
```

The `newGuid()` admin password is hex + hyphens, so it needs no ADO.NET
quoting. NOTE: when `administratorPassword` defaults from `newGuid()` (see
main.bicep), the password rotates on every deploy — self-consistent within a
run, but any manually copied connection string goes stale; README and the
`.env.local` comments must say to re-copy from Key Vault after each
deployment.

## `infra/modules/storage.bicep` (only when file/upload storage was chosen)

Provisions a Storage Account (`Standard_LRS`) and a blob container, with
blob soft-delete and versioning turned on (see the ALWAYS list in
`decision-matrix.md` — this is the storage side of "what if someone deletes
a file by accident"). Output: `connectionString`.

## `infra/modules/containerapp.bicep`

Provisions:
1. A Container Apps Environment (Consumption plan), with its
   `appLogsConfiguration` wired to the Log Analytics workspace
   `appinsights.bicep` created (via the `logAnalyticsWorkspaceId` param
   passed through main.bicep).
2. A Container App that pulls from the ACR provisioned above.

The Container App should:
- Tag the Container App resource itself with
  `union(tags, { 'azd-service-name': 'app' })` — REQUIRED: this tag is how
  `azd deploy` locates the target resource for the `app` service in
  `azure.yaml`. Without it, provisioning succeeds and deploy then fails with
  "unable to find a resource for service 'app'".
- Use `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` as the
  placeholder image — NEVER an image path in this app's own registry: on the
  very first `azd up`, provisioning runs before any image has been pushed to
  the brand-new registry, so a self-referencing placeholder fails the whole
  deployment with an image-pull error. `azd deploy` swaps in the real image
  as a new revision immediately after. (A later full re-provision briefly
  resets to this placeholder until deploy replaces it — normal azd behavior;
  someone viewing the dev site may see the hello-world page for a moment.)
- Configure ingress: `{ external: true, targetPort: 3000 }` (8000 for
  Python). Even staff-only apps need external ingress — the user's browser
  must reach the app to perform the Hydra login redirect.
- Do NOT define liveness/readiness probes on the Container App. Every
  provision (first run AND re-provisions) creates the revision with the
  `containerapps-helloworld` placeholder image above, which serves on port
  80 and has no `/api/health` route — probes pointed at the app's real port
  (3000, or 8000 for Python) would never pass, so the revision could never
  become healthy and provisioning would time out. External health
  monitoring of `/api/health` is handled by the availability test in
  monitor.bicep instead.
- Set minReplicas/maxReplicas per the ALWAYS-list rule in
  `decision-matrix.md` (0 or 1 / 3, decided from the USERS answer).
- Reference Key Vault URI as an environment variable.
- Set `APPLICATIONINSIGHTS_CONNECTION_STRING` from the
  `appInsightsConnectionString` param.
- Use the pre-created USER-ASSIGNED managed identity, passed in as the
  `userAssignedIdentityId` param (see identity.bicep and main.bicep) — NOT a
  system-assigned identity. Set:
  ```bicep
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${userAssignedIdentityId}': {} }
  }
  ```
- Do NOT create the "Key Vault Secrets User" or AcrPull role assignments in
  THIS module. They are already granted to the app identity in
  `keyvault.bicep` and `registry.bicep` respectively, so they exist BEFORE
  this Container App is created. Creating them here instead — the way a
  system-assigned identity forces, since its principalId doesn't exist
  until the app does — is exactly the deadlock identity.bicep describes; do
  not reintroduce it.
- Set `properties.configuration.registries`:
  `[{ server: <loginServer>, identity: <userAssignedIdentityId> }]` — the
  pull uses the user-assigned identity (which already holds AcrPull); use
  that identity's resource id here, never `'system'`. Without this the
  Container App has no way to PULL its image (the registry's admin user
  only covers azd's push side).
- When login was chosen, set the OIDC public config as plain runtime env
  vars — `NEXT_PUBLIC_AUTH_URL`, `NEXT_PUBLIC_CLIENT_ID` (and
  `NEXT_PUBLIC_REDIRECT_URL` for symmetry) — sourced from bicep params
  (`authUrl`/`clientId`/`redirectUrl`), which come from
  main.parameters.json. These are NOT secrets, so they're direct env
  values, not secretRefs. This is required, not optional: the API-route
  token verifier reads them from `process.env` at runtime, and the build
  args alone (which only feed the browser bundle) leave the server side
  unset — the symptom is every authenticated route returning 401 "Missing
  required environment variable: NEXT_PUBLIC_AUTH_URL". See the Dockerfile
  comment in `scaffold-web-nextjs.md` for why build-time inlining doesn't
  cover the server read.
- For each provisioned data store, define a Container App secret that
  points at the Key Vault secret URI (`keyVaultUrl` + identity — use the
  SAME `userAssignedIdentityId`, never `'system'`) and map it to the
  matching env var (`DATABASE_URL`, `AZURE_STORAGE_CONNECTION_STRING`) so
  the running app reads a live connection with no manual configuration.
- For each external-integration secret (see EXTERNAL INTEGRATION SECRETS in
  main.bicep above), define the same kind of Container App secret + env var
  mapping (e.g. `BANNER_API_URL`, `BANNER_API_KEY`), pointed at the
  placeholder Key Vault entry `keyvault.bicep` created. The app reads
  whatever value is currently in Key Vault — a placeholder until IT sets
  the real one, the real credential afterward — with no code change or
  redeploy required, only a Container App restart/new revision to pick up
  a value IT just changed.

Outputs: `uri` (the Container App's ingress URL), `name` (used by
`monitor.bicep` to target the health alert at this app).
