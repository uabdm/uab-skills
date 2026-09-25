---
name: uab-secret-demo
description: Proves, end to end, that Daytona's Secrets feature works in this TrueForge sandbox — that a script running inside the sandbox can make an authenticated call to a real external API using a credential it never actually holds (Daytona's outbound proxy substitutes the real value for an opaque placeholder, only for HTTPS request headers, only to an allowlisted host). This is a test/demo skill, not a production integration — it exists to give a concrete, verifiable answer to "can the sandbox call an API with an injected secret" and to show what the sandbox's own environment variable actually contains (a placeholder, never the real key). Use when asked to "test the Daytona secret injection," "demo calling an API with a secret from the sandbox," "prove the sandbox can use an injected API key," or similar. Not related to uab-deploy's GitHub MCP connector — that's a separate, already-working mechanism this skill doesn't touch or replace.
---

# UAB Secret Demo — prove Daytona's Secrets substitution works

This skill has exactly one job: call a real external API from inside this Daytona sandbox,
authenticated with a credential that was never actually placed in the sandbox as plaintext —
and show the result plainly enough that it's obvious whether it worked or not. It exists to
demonstrate Daytona's **Secrets** feature (see `daytona.io/docs/en/secrets/`), which is
architecturally different from — and more protective than — just setting a plain environment
variable to a real API key:

1. A secret is created once in the Daytona organization (Dashboard or SDK), encrypted at
   rest, and assigned an opaque placeholder token (e.g. `dtn_secret_<random>`).
2. This sandbox's environment variable holding that secret is set to the **placeholder**,
   never the real value.
3. When this sandbox makes an outbound HTTPS request whose header carries the placeholder
   unmodified, Daytona's proxy substitutes the real value **only if the destination host is
   on that secret's configured allowlist** — the sandbox process itself never sees the
   plaintext.
4. Responses are scrubbed too: if the real value would ever appear in a response, the proxy
   rewrites it back to the placeholder first, so it can't be extracted by reflection.

**What this is not:** not a production API-calling pattern for real integrations, not related
to `uab-deploy`'s GitHub push mechanism (which goes through TrueForge's GitHub MCP connector
and is a completely separate, already-working flow — this skill doesn't touch it), and not
something other skills should call into.

## Hard limits of this mechanism — don't fight these, design around them

- **Headers only.** Query parameters and request bodies are forwarded unmodified by Daytona's
  proxy. An API that only accepts its key in the URL (`?api_key=...`) or JSON body cannot be
  authenticated this way.
- **No transforms.** Substitution is a literal match on the unmodified placeholder. Anything
  that derives a header value from the secret client-side — HTTP Basic Auth helpers that
  Base64-encode it, or a signed scheme like AWS SigV4/HMAC that hashes it with request-specific
  data — breaks this, because the proxy never sees the placeholder unmodified in the header.
- **Never use an echo/reflect-your-headers-back endpoint to "prove" this works.** Because
  responses are scrubbed, an echo service will show the placeholder even on a successful
  substitution — that looks like failure but isn't. Always test against a real endpoint whose
  success genuinely depends on the credential (a 200-with-real-data vs. 401 signal).

## One-time setup this skill depends on (outside this skill's own control)

1. In the Daytona Dashboard (or via `daytona.secret.create(...)`), create a secret holding a
   real GitHub personal access token, with `hosts=["api.github.com"]` — no special scopes
   needed, this only calls `/user`. Use a token separate from whatever `uab-deploy`'s GitHub
   MCP connector uses; they're unrelated.
2. Attach that secret to this agent's sandbox, mapped to the environment variable
   `DEMO_API_TOKEN` (the SDK's `secrets={"DEMO_API_TOKEN": "<secret-name>"}` parameter,
   distinct from a plain `env_vars` mapping). **Whether TrueForge's own sandbox-provisioning
   UI exposes this attachment step is not confirmed** — check `Settings` for something beyond
   `Sandbox providers` (e.g. a "Sandbox environments" section) before assuming it's reachable
   from here. If a secret was just attached to a sandbox that had none before, it needs a
   restart before the new value takes effect; a sandbox that already had secrets picks up
   changes within seconds.

## What the script does

Run `scripts/call-api.sh` — the single entry point, never hand-call `curl` in its place, so
the same interpretation logic (PASS/FAIL reasoning below) is applied consistently every time.

It calls `https://api.github.com/user` with `Authorization: Bearer $DEMO_API_TOKEN` and reads
the HTTP status code:

- **200** — the real credential was substituted correctly by Daytona's proxy. This is the
  positive proof: the sandbox authenticated as a real GitHub account without ever holding
  that account's real token.
- **401** — substitution did not happen. Most likely causes, in order to check: the secret
  isn't attached to this sandbox at all, it was just attached and the sandbox needs a
  restart, the host allowlist doesn't include `api.github.com`, or the underlying token
  itself is invalid/expired.
- **anything else** — report the actual status code plainly; never guess at what it means.

**Never print `$DEMO_API_TOKEN`'s own value in any output** — even though it should only ever
be the opaque placeholder, keep the same never-print-a-credential-shaped-value habit used
throughout this skill family. If asked to prove the substitution point concretely, printing
the env var's value alongside the call result is fine and useful *precisely because* it will
visibly be a `dtn_secret_...`-shaped placeholder, never anything that looks like a real token
— that contrast is the demo.

## Report back

Plain language: what was called, what came back (status code), and the one-sentence
interpretation (substitution worked / didn't / inconclusive). If this is being run as a
demonstration, explicitly offer to also show the raw placeholder value from the environment
variable alongside a successful call — that side-by-side (opaque placeholder in the
environment, real authenticated response from GitHub) is the actual proof, not just a bare
"PASS."
