# Reliability: no flakes

A flaky check is a broken check. Each red-then-green re-run trains people to
ignore red, and the real failure then merges.

## No blanket retries

- Never wrap the test command in a retry loop, and never enable a runner's
  auto-retry (`nextest` `retries`, `pytest-rerunfailures`, jest
  `retryTimes`) for the whole suite.
- Retry is allowed only around a known-transient **infrastructure** step:
  downloading a toolchain, pulling an image, pushing to a cache. Use bounded
  backoff (3–4 attempts) and log every retry.
- If a runner's retry is used to *detect* flakes, the job must still fail
  when a test only passed on retry. nextest labels these `FLAKY` in its
  output; make the job fail when any appear. A retry that turns red into a
  silent green hides the bug.

| Excuse | Why it doesn't hold |
|---|---|
| "It passes on re-run, so the code is fine" | Something in the test or code is nondeterministic. The re-run just did not hit it. |
| "It only fails in CI" | CI is the environment that exposes timing, ordering and resource limits. That is the finding. |
| "We'll retry for now and fix it later" | Later never comes once the check is green. Quarantine has an owner and a date; a retry has neither. |

## When a check goes red without a code cause

1. **Look at the default branch's history first.** If the same check failed
   the same way on `main` before your change, it is pre-existing. Do not
   bisect your own diff for it.
2. **Separate infrastructure from tests.** "No space left on device", OOM
   kills, a runner losing its connection to a daemon, or a registry 5xx are
   infrastructure. Fix the runner (disk headroom, garbage collection,
   memory limits), not the test.
3. **Reproduce it.** Run the one test in a loop under the CI conditions:
   parallel, the same CPU limit, a cold cache. A flake that never reproduces
   has not been understood.
4. **Fix the cause** (see `testing`'s determinism rules): shared global
   state, fixed ports, wall-clock waits, test ordering, unawaited tasks.

## Quarantine

When the fix cannot land today, quarantine instead of retrying:

- Move the test to a separate, non-required job that still runs and still
  reports, or mark it skipped with a reason.
- Record an owner and an issue link next to the skip.
- Keep the list visible and short. A quarantined test that has had no work
  for a few weeks is deleted or fixed, not left to rot.

## Make flakes impossible by construction

- Every await on a network, channel or process has a timeout.
- Tests bind port 0 and read back the address.
- Tests get their own temp directory and never write to a shared path.
- Time and randomness are injected; random seeds are printed on failure.
- Run the suite in random order (or at least in parallel) in CI, so
  order dependence fails early, not months later.
