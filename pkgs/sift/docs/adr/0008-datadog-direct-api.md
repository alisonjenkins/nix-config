# ADR 0008: Query Datadog directly over its HTTP API, not by shelling out to `pup`

## Status

Accepted

## Context

ADR 0002 scoped `sift`'s MVP to Loki + Prometheus/Mimir and deferred
Datadog. Work observability (per `related-repos.md`/machine config) is
Datadog, not LGTM, and `home/skills/observability/platforms/datadog.md`
already told agents to run `sift datadog logs|metrics|traces` before
that surface existed — the skill document was ahead of the tool.

Two shapes were available for closing that gap:

1. **Shell out to `pup`** (Datadog's own CLI, already used for
   interactive investigation per the `observability` skill). Reuses
   `pup`'s OAuth login, but reintroduces exactly the problem ADR 0006
   solved for LGTM: `sift` would either need to hold or forward a
   credential itself, or trust `pup`'s own session state, and its
   output shape (human-formatted, versioned independently of `sift`)
   is not something `parse_*_response(body: &str)` can be written
   against with a stable fixture.
2. **Call the Datadog HTTP API directly**, the same pattern `loki.rs`
   and `prometheus.rs` already use: a `reqwest::blocking` client, a
   pure `parse_*_response` function per endpoint tested against a
   fixture string, and credentials resolved via secretspec exactly like
   ADR 0006 established for LGTM.

## Decision

`src/platform/datadog.rs` implements all three signals via direct HTTP
calls, following the same shape as `loki.rs`/`prometheus.rs`:

- **Logs**: `POST /api/v2/logs/events/search`, paginating via
  `meta.page.after` → `page.cursor`.
- **Metrics**: `GET /api/v1/query` (v1 timeseries query — no
  pagination, matches the LGTM Prometheus adapter's shape).
- **Traces**: `POST /api/v2/spans/events/search`, paginating the same
  way as logs.

The request/response shapes were verified against
`DataDog/datadog-api-client-go`'s generated model structs (itself
generated from Datadog's published OpenAPI spec), not from prose docs
alone — `docs.datadoghq.com`'s rendered API reference pages did not
expose the underlying JSON schema to a page fetch, so the generated
client's Go structs were used as the authoritative source instead. See
the Consequences section for what remains unverified.

Credentials: `--auth-profile` (env `SIFT_DD_AUTH_PROFILE`) resolves
`DD_API_KEY`/`DD_APP_KEY` via secretspec, the same mechanism ADR 0006
built for LGTM — `pkgs/sift/secretspec.toml`'s `default`/`personal`/`work`
profiles all declare both secrets now. Unlike LGTM, Datadog's API
rejects an unauthenticated request outright, so there is no "no
credentials" fallback: omitting `--auth-profile` still resolves via
secretspec's `default` profile, which is bound to the `env` provider —
so a plain `DD_API_KEY`/`DD_APP_KEY` in the environment works with no
profile at all. A missing key produces `AuthError::MissingDatadogKey`
naming exactly which one, before any request is sent. Both keys go into
request headers (`DD-API-KEY`, `DD-APPLICATION-KEY`) only — never
logged, matching `Auth`'s existing hygiene (ADR 0007).

`DatadogError` is one `thiserror` enum for the whole module (mirroring
how `LokiError`/`PrometheusError` cover both `parse_*` and `fetch` in
one file), with per-signal, per-site variants
(`Logs{Request,ResponseRead,Status,RateLimited,Parse,ApiError,
MalformedTimestamp}`, and the equivalent `Metrics*`/`Traces*` sets) —
no variant is shared across signals, so a caller can always tell which
endpoint and which failure mode produced an error.

`--group-by` defaults differ per signal, since the same reduction flags
now have to serve three different query shapes: `status` for logs,
`metric` for metrics, `service` for traces — see the doc comments on
`cli.rs`'s `DatadogLogsArgs`/`DatadogMetricsArgs`/`DatadogTracesArgs`.
Logs and traces follow Datadog's `meta.page.after` cursor, 1000 events
per request. `--mode raw` stops at `--limit`; every other mode stops at
`--max-events` (default 5000) rather than paging a live Datadog org
indefinitely. Results are fetched newest first, so a capped fetch drops
the oldest part of the window, and sift warns on stderr when a reducing
mode hits the cap, since its counts are then not totals for the window.
Exact counts over a large window belong to Datadog's server-side
aggregate endpoints (`/api/v2/logs/analytics/aggregate`,
`/api/v2/spans/analytics/aggregate`), which sift does not call yet.

## Consequences

- Running `sift datadog ...` needs `DD_API_KEY`/`DD_APP_KEY` with
  read-only scopes stored in 1Password (personal) or SSM (work) — see
  `pkgs/sift/docs/credential-profiles.md`. `pup`'s existing OAuth login
  is not reused by `sift`; the two tools authenticate independently.
- `sift` stays a single self-contained binary with one credential path
  (secretspec) and one test style (fixture-string `parse_*_response`
  tests, no network in `cargo test`) across every platform it supports,
  rather than `pup`'s output format becoming an implicit, unversioned
  part of `sift`'s own contract.
- Two gaps in verification, both called out at the failure sites they'd
  affect rather than hidden: (1) the logs filter's `from`/`to` fields
  are documented in the generated client only as "date math and regular
  timestamps (milliseconds)," not explicitly as accepting RFC3339 —
  unlike the spans filter, whose doc comment explicitly allows
  "date-time ISO8601." `sift` sends RFC3339 for both; this is very
  likely correct (RFC3339 is accepted elsewhere in Datadog's API
  surface) but has not been confirmed against a live logs query. (2)
  the exact `X-RateLimit-Reset` header name/format on a 429, and the
  JSON:API `{"errors":[...]}` envelope `parse_logs_response`/
  `parse_traces_response` check for, follow Datadog's documented v2
  convention but were not confirmed against a captured live response
  body.
