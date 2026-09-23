# `README.md`

Write in plain English. Avoid jargon where possible. Structure:

```markdown
# <App Name>

## What this app does
(from the project leader's description)

<<< ONLY if DATA SENSITIVITY (Q7) flagged this app, insert this section
    here: >>>
### Before you go live
This app is expected to handle [the flagged category — see
decision-matrix.md]. Get sign-off from [the mapped office] before treating
this as production-ready for real use — building, testing, and even running
this locally can continue in the meantime, but don't point real users or
real data at it until that review is done.

## Running this locally
1. Install dependencies: `npm install` (or `pip install -r requirements.txt`)
2. `.env.local` is already generated (gitignored, not included in the
   handoff zip) with everything that can be filled in locally. If this app
   has a login, the Hydra values are already real and working — no setup
   needed. Data storage works with nothing to configure — it saves to a
   local file automatically (see below). For an external system
   integration, add a real test credential to `.env.local` if you want to
   test that integration locally — leave it blank to skip. Never put a
   real value in `.env.template` — it documents variable names only.
3. Run it: `npm run dev` (or `uvicorn app.main:app --reload`)
4. Health check: http://localhost:3000/api/health (or
   http://localhost:8000/health)

## Where this app stores its data
<<< ONLY if a data store was generated — see DATA STORAGE in
    decision-matrix.md >>>
This app saves its data to local files inside the project folder — a
SQLite database file and/or an uploads folder, depending on what it stores
(see `data-layer.md` for exactly which). Nothing needs to be installed or
configured for this to work. If this app is later moved to a shared server
so multiple people can use it at once, that local storage should be
replaced with a real hosted database — that's a follow-up step for a
developer, not something this file walks through.

<<< ONLY if Q6 = B or C, insert this section: >>>
## Systems this app needs access to
For each named system: `<system name>` — contact the system owner/data
steward for the API key or credentials this app needs, then put them in
`.env.local` (gitignored, never committed, never included in the handoff
zip) using the variable names listed in `.env.template`.

<<< ONLY if login was generated: >>>
## Signing in
This app uses UAB's Ory Hydra single sign-on (BlazerID). Locally, sign-in
already works with no setup — `.env.local` ships with real, working values
pointed at UAB's identity server. If this app is later deployed somewhere
permanent, whoever deploys it needs to register `<hydra-client-id>` as a new
client with UAB's Ory Hydra OAuth2 server for that deployment's URL, and set
`NEXT_PUBLIC_AUTH_URL`, `NEXT_PUBLIC_CLIENT_ID`, and
`NEXT_PUBLIC_REDIRECT_URL` to that environment's values (these are
build-time values baked into the browser bundle when the app is built — see
`.env.template`).
No separate post-logout redirect URI needs to be registered — signing out
intentionally lands the user on Hydra's own logged-out page rather than
bouncing back into the app (same behavior as UAB's other production apps).
If this app is for "our team / staff only," every page requires signing in
first — there is no public homepage to preview before logging in.

## Deploying this app somewhere permanent
This generator hands off source code for a quick proof-of-concept or demo —
it does NOT install dependencies, build, run, or otherwise verify that this
code works before handing it to you, and it does not set up Azure
infrastructure, a deployment pipeline, or any hosting. Before relying on
this beyond a demo, run `npm install` (or `pip install -r requirements.txt`)
and build it for real. Getting this app running somewhere everyone can
reach it (Azure, another cloud, an on-premises server) is a separate step
for a developer or your IT team, who can containerize it (a Dockerfile is
included) or deploy it using their own standard process.

## Fonts
This app uses the UAB brand fonts `kulturista-web` and `proxima-nova` via
Adobe Typekit — already wired up and working out of the box (see the
`<link>` tag in `src/app/layout.tsx`'s `<head>`); no setup needed for local
development. If this app is later deployed to a domain outside UAB's
existing Typekit kit configuration, confirm that domain is on the kit's
allowed-domains list in Adobe's dashboard — on a domain the kit doesn't
recognize, the app still works but silently falls back to system fonts.

## Who to contact about this project
The name/email and department from Q11.
```
