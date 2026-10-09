# 0034. Run the observability stack as one pod with `podman kube play`

- Status: Accepted, pending the macOS spike (T005)
- Date: 2026-10-09

## Context

Spec 007 wants Loki, Tempo, Prometheus and Grafana (plus an OpenTelemetry
Collector) running locally in containers, declared in Nix, on NixOS,
non-NixOS Linux (home-manager only) and macOS, with one option set. The aim is
to find where Claude Code spends tokens.

Podman is already opt-in on Linux (`modules/podman`); macOS has no container
runtime in this repository.

## Decision

`home/modules/observability-stack` renders one Kubernetes-style Pod definition
from the module options and runs it with `podman kube play` on every OS. Only
the supervisor differs: a systemd user service on Linux, a launchd agent on
macOS that first creates and starts the podman machine.

Config files are copied from the Nix store into the data directory before each
start and bind-mounted from there, because the podman machine on macOS shares
the home directory and not `/nix/store`.

On macOS the stack runs in its own podman machine (default name `observability`,
2 CPUs, 4 GiB, 30 GiB disk) so it never shares or resizes a machine used by other
tools. Sizing applies only when the machine is created; changing it needs
`podman machine rm <name>` first, and no data is lost because the stores live in
the data directory, not the VM.

The containers share the pod's network, reach each other on `localhost`, and
only the configured ports are published, on `127.0.0.1` unless
`exposeBeyondLoopback` is set. Containers run as container root, which rootless
podman maps to the host user, so the bind-mounted data stays owned by the user.

## Alternatives rejected

- **Home Manager `services.podman.containers` (Quadlet).** Clean on Linux but
  systemd-only, so macOS would need a second definition of every service.
- **NixOS `virtualisation.oci-containers`.** Rootful, NixOS only; covers neither
  non-NixOS Linux nor macOS.
- **Docker Desktop, OrbStack, colima, Apple `container`.** None of them runs
  `podman kube play`, so using one means a second pod definition next to the
  Linux one and the single source of truth is gone. This holds for a user who
  already runs Colima; it is not about maintenance cost.
- **Native nixpkgs services under systemd and launchd.** Simplest and avoids the
  macOS VM, but the owner asked for containers. Kept as the fallback if the
  macOS spike fails.
- **`grafana/otel-lgtm`.** A demo image with no per-service retention control.

## Consequences

One definition to test: a pure check renders it and asserts digests, loopback
binding, retention and datasources, and another feeds the rendered configs to
the real Loki, Tempo, Prometheus and collector binaries. What the checks cannot
cover is the runtime (podman machine, container networking, real ingest); that
is a named manual step in the quickstart.

The cost on macOS is a second VM next to any Colima or Kind one, and the machine
reserves its memory. podman's documentation says it runs one machine at a time on macOS, so the runner refuses to start (it never stops anything) while another podman machine is running; this is from the documented behaviour and has not been verified on the owner's Mac (spike T005). Consolidating onto one machine later means moving Colima and
Kind onto a podman machine (Kind's podman provider is experimental and needs a
rootful machine), never the reverse, because only podman can run `kube play`.

Images are pinned by manifest-list digest, so a bump is a deliberate edit of
`images.nix`.

## Evidence

- `nix build .#checks.x86_64-linux.observability-stack-render`
- `nix build .#checks.x86_64-linux.observability-stack-config-validate` caught a
  removed collector option (`service.telemetry.metrics.address`) the first time
  it ran.
- Round trip on native binaries, 2026-10-09: OTLP metrics, logs and traces
  accepted by Prometheus, Loki and Tempo with the rendered key names
  (`specs/007-local-observability-stack/research.md`, "Spike results").

## Revisit when

`podman kube play` does not work with a podman machine on macOS (bind mounts,
`--replace`, restart after a VM reboot), or a declarative macOS runtime with a
home-manager module appears.
