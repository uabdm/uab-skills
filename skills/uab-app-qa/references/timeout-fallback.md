# Timeout escalation: when to stop and ship a zip instead

`uab-app-creator`'s own `verify-web-app.sh` skips `npm run build` and
starting a dev server entirely because a cold build or a long-lived
dev-server+curl loop was the confirmed cause of sandbox timeouts on its
generation sandbox. This skill exists specifically to run those steps
somewhere that should be able to handle them — but "should" isn't a
guarantee. Some environments this skill runs in turn out to have the same
constraint (a hard wall-clock limit on the whole session, a per-command
timeout even the `bg-run.sh`/`Bash run_in_background` detachment trick
can't outrun, or a resource-starved sandbox where a build simply never
finishes). When that's what's actually happening, don't keep retrying the
same command hoping the next attempt is different — recognize it and ship
what you have.

## Priority order — always bank Phase 1 first

Run phases strictly in order (Phase 0 → 1 → 2 → 3 → 4), and treat Phase 1
(install + `npm audit`) as the step to protect above all else: it's the
cheapest phase, it's the one most likely to actually finish even in a
constrained sandbox, and its output — a `package.json`/`package-lock.json`
with vulnerabilities patched — is real, durable value on its own even if
nothing downstream can run. **An app whose dependencies were installed and
audited but never build-tested is a strictly better handoff than an app
that was never touched at all**, so never let a struggling Phase 2 or
Phase 3 stop you from having already banked Phase 1's result. Concretely:
finish Phase 1 completely (loop it to a real PASS or a clearly-reported
unresolved-finding FAIL) before spending any time on Phase 2, even if you
already suspect this sandbox will struggle with the build.

## Recognizing a real timeout pattern, not a fluke

One slow command isn't a pattern. Treat it as a genuine sandbox-timeout
situation — not a one-off to shrug off and retry — once **either**:

- The same command (install, build, or dev-server start) has been
  attempted twice **and** timed out, errored on a wall-clock/timeout basis,
  or (via `bg-status.sh`) sat at `RUNNING` for well past a sane multiple of
  its normal duration (a rough guide: ~15 minutes with no log progress for
  an install, ~20 minutes for a build, ~5 minutes for a dev server that
  still hasn't printed its "ready" line) on **both** attempts, or
- Two *different* phases (e.g. both the install and the build) have each
  hit a timeout independently — a strong signal this is the sandbox itself,
  not one flaky command.

A single timeout is worth one retry (ideally backgrounded, if it wasn't
already) — transient network slowness on a registry fetch is real and
usually clears up. It's the *second* consecutive timeout on the same
command, or a *second phase* also timing out, that means stop retrying and
escalate.

## What to do once you've recognized it

1. Stop attempting the phase that's timing out. Don't keep looping it — a
   third identical attempt is very unlikely to behave differently from the
   first two.
2. Make sure Phase 1's fixes are actually reflected in the working tree
   (they will be — `npm audit fix` writes straight to
   `package.json`/`package-lock.json` — but confirm you didn't leave it
   mid-fix if that's the phase that was still running when this triggered).
3. Package the app for handoff: `scripts/package-for-handoff.sh` (see its
   own header for what it includes/excludes — notably, it keeps
   `package.json`/`package-lock.json` exactly as Phase 1 left them, and
   excludes `node_modules` so the zip itself doesn't balloon or itself risk
   a timeout while compressing gigabytes of installed packages).
4. Report exactly what happened — see the next section. Do not say the app
   is "done," "working," or "clean." Say precisely which phases actually
   completed and passed, which one(s) hit the sandbox limit, and that the
   packaged zip is the deliverable for continuing the remaining phases
   somewhere without this constraint (the person's own machine, a CI
   runner with a longer/no timeout, a different sandbox).

## Reporting a timeout-fallback outcome (feeds Phase 5)

State plainly, in this order:
- Which phases actually ran to completion and passed (e.g. "Phase 0 and
  Phase 1 completed: dependencies installed, `npm audit` clean" or "...,
  found 2 high-severity findings and fixed both via `npm audit fix`").
- Which phase hit the timeout, how many attempts, and what the actual
  symptom was (a hard error message, or `bg-status.sh` still showing
  `RUNNING` after the elapsed time noted above).
- The path to the packaged zip (`scripts/package-for-handoff.sh`'s output
  path) and that `node_modules` is excluded — the receiving environment
  needs to run `npm install` again before it can build or start the app.
- What still needs to happen there: run this skill again (or its remaining
  phases by hand) in an environment without the timeout constraint.

Never let a timeout-fallback outcome read like a clean pass. The zip is a
handoff of work-in-progress, not a certification that the app works.
