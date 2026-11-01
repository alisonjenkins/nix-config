# 0052. Treat a store's first readiness answer as a probe artefact, not an outage

- Status: Accepted
- Date: 2026-10-25

## Context

The local observability stack runs Loki, Tempo, Prometheus, Grafana, and an
OpenTelemetry Collector as one pod under rootless podman. Prometheus scrapes
`/metrics` from each store, but does not scrape `/ready`.

On 2026-10-25T11:32:09Z, `cc-obs-query health` reported Loki and Tempo `down`
while Prometheus was `up`. All five pod containers had been running since
2026-10-24T09:21Z (26 hours) without restarts or suspends. A weekly token review
started with two stores reported down, with no indication of why. A bare `down`
gave no way to distinguish a failed process from a sleeping readiness timer.

Loki and Tempo build their ingesters on `grafana/dskit`'s ring lifecycler. Its
`CheckReady` method initializes `readySince` on the first call to `/ready`. It
then returns HTTP 503 "waiting for 15s after being ready" until
`min_ready_duration` (default 15 s) passes from that first call. A store running
idle for a day still returns 503 on its first probe and for the next 15 seconds.
The guard exists for rolling restarts in distributed clusters. It adds no value
to a single local instance.

## Decision

Set `ingester.lifecycler.min_ready_duration = "0s"` for Loki and Tempo in
`home/modules/observability-stack/configs.nix`.

Update `cc-obs-query health` to include a `reason` field on every `down` row with
the HTTP status code and upstream response text. Include the store name and
reason in digest gap reports. A readiness `down` without an explicit reason is a
bug in the probe tool, not an outage of the stack.

## Alternatives rejected

- **Retry in health checks for 20 seconds on HTTP 503.** Retrying hides the
  underlying mechanism and delays every initial run. It still leaves rows bare if
  a store fails permanently.
- **Prime `/ready` in the start script after `podman kube play`.** Priming only
  protects the first 15 seconds after launch. It leaves dskit behavior
  undocumented and fails if an instance starts without the runner.
- **Use Prometheus `up` metrics instead of `/ready`.** Prometheus `up` checks
  metric scrape success, not query readiness. It also creates a strict dependency
  on Prometheus availability.

## Consequences

- The first probe to Loki or Tempo returns HTTP 200 as soon as the ring is
  healthy.
- Real not-ready conditions, such as WAL replay or broken ring states, still
  return HTTP 503 and report the actual cause string.
- The readiness 503 counters (`*_request_duration_seconds_count{route="ready",
  status_code="503"}`) now only move when a store was probed while genuinely not
  ready, such as during WAL replay right after a start. A value that grows while
  the pod has been up for a while is worth a look.

## Evidence

- At 2026-10-25T11:32:09Z, all five pod containers had run for 26 hours.
  `podman ps` showed 26 h uptime, and `process_start_time_seconds` remained flat.
- Journal logs showed no system suspends, clock changes, or container restarts.
  Process swap residency remained below 4 MB for Loki and Tempo. Pod cgroup I/O
  pressure was zero. Prometheus `up{job=~"loki|tempo"}` was 1 throughout.
- Prometheus series `loki_request_duration_seconds_count{route="ready"}` and
  `tempo_request_duration_seconds_count{route="ready"}` did not exist before
  2026-10-25T11:33Z. Nothing had probed `/ready` since startup. At 11:33Z, both
  series appeared with status 503 = 2 and status 200 = 1. The first two probes
  received 503, and the third probe 34 seconds later received 200.
- `grafana/dskit` `ring/lifecycler.go`: `CheckReady` is the only code that sets
  `readySince` (`if i.readySince.IsZero() { i.readySince = time.Now() }`), and it
  returns `waiting for %v after being ready` until `MinReadyDuration`
  (flag `min-ready-duration`, default 15 s) has elapsed since that first call.
- Reproduced on 2026-10-25T11:49Z with a throwaway `grafana/loki:3.7.8` container
  on the stack's own `loki.yaml`: left idle for 60 s, the first `GET /ready`
  answered 503 `Ingester not ready: waiting for 15s after being ready`, a probe
  2 s later answered the same, and a probe at 78 s answered 200 `ready`.
- Tempo 2.10.8 returns a Go nil-pointer panic in `statusHandler` (app.go:418)
  and resets the connection on `GET /status/buildinfo`. The process stays alive.
  Probes must query `/ready` or `/status`, never `/status/buildinfo`.

## Revisit when

A store upgrade removes `min_ready_duration` from the ring lifecycler, or the
observability stack scales to multiple instances per store.
