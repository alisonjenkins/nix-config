# Documentation

Documentation, runbooks, architecture decision records, specifications, and benchmarks for this configuration.

## Subsystems

- [Subsystem pointers](./subsystems.md): Directory of code, documentation, and decisions across all major repository subsystems
- [Memory recall](./memory-recall.md): Semantic recall system for agent memories and skills using vector embeddings
- [AI control centre](./ai-control-centre.md): Process overview and event-driven session monitor in claude-monitor
- [Observability stack](./observability-stack.md): Local containerized Loki, Tempo, Prometheus, and Grafana telemetry deployment
- [Local model capabilities](./local-model-capabilities.md): Capability and safety evaluations of candidate local LLMs running on Vulkan
- [Spec-Kit setup](./spec-kit-setup.md): Integration guide and packaging for Spec-Kit with Claude Code and GitHub Copilot CLI

## Hosts and hardware

- [ali-desktop boot time](./ali-desktop-boot-time.md): Boot phase profiling, LUKS keyslot optimization, and timing analysis
- [Fix broken Nix store on ali-desktop](./ali-desktop-fix-broken-nix-store.md): Live-disk recovery steps to mount the root filesystem and repair the Nix store
- [ali-desktop GPU tuning and hang triage](./ali-desktop-gpu.md): RX 9070 XT voltage curves, kernel parameters, and DRM hang diagnostics
- [Hardware video on ali-mba-linux](./ali-mba-linux-hardware-video.md): VA-API hardware video decode configuration on Asahi Linux
- [Pull and build this system](./nix-pull-build.md): Shared workflow and skill to pull latest changes and rebuild system configurations

## Streaming and gaming

- [Steam Remote Play at client resolution](./steam-remote-play-streaming.md): Architecture for streaming to handhelds at native resolution alongside an ultrawide monitor
- [Remote Play troubleshooting](./remote-play-troubleshooting.md): Symptom-first triage and recovery steps for streaming issues
- [Declarative Beat Saber mods](./beatsaber-mods.md): Pinned BSIPA and BeatMods mod management through home-manager
- [Positional audio benchmark](./positional-audio-bench.md): Objective localization benchmark for PipeWire binaural surround virtualization

## Hetzner and Kubernetes

- [Rolling back an encrypted volume migration](./hetzner-encrypted-volumes-rollback.md): Recovery procedures before and after old volume removal
- [Patching Hetzner master without downtime](./hetzner-inplace-patching-design.md): In-place master maintenance design sketch and outage mitigation
- [Hetzner master live maintenance](./hetzner-k3s-live-maintenance.md): Applying k3s unit updates and datastore compaction without downtime
- [Restore Minecraft world from Velero backup](./hetzner-minecraft-world-restore.md): Restoring quiesced game data from object storage backups

## Benchmarks

- [MoE offload benchmark](./moe-offload-benchmark.md): Evaluation of large language model offloading techniques on limited VRAM
- [PowerInfer on ROCm benchmark](./powerinfer-rocm-benchmark.md): Performance evaluation and bug validation of PowerInfer under ROCm

## Architecture decision records

Architectural decisions are tracked in `docs/adr/`. The recording process is established in [0001. Record decisions as ADRs](./adr/0001-record-decisions.md), and the rest of docs/adr/ holds 53 numbered ADRs (54 numbered ADRs in total).

| Number | Title |
| --- | --- |
| 0001 | [Record decisions as ADRs](./adr/0001-record-decisions.md) |
| 0002 | [Stream from a declared niri virtual output](./adr/0002-virtual-output-for-remote-play.md) |
| 0003 | [Correct Steam's desktop geometry in SDL, not X](./adr/0003-steam-display-filter.md) |
| 0004 | [Publish the stream target as files under `~/.local/state`](./adr/0004-stream-target-files.md) |
| 0005 | [One event-driven watcher owns all stream state](./adr/0005-stream-mode-owns-stream-state.md) |
| 0006 | [Map Remote Play input to global coordinates in extest](./adr/0006-extest-remote-play-input.md) |
| 0007 | [Stream games in game mode, without gamescope](./adr/0007-remote-play-game-mode.md) |
| 0008 | [Give Steam a newer libva, and only Steam](./adr/0008-steam-libva.md) |
| 0009 | [Let bubblewrap run under gamescope's capabilities](./adr/0009-gamescope-capabilities-and-bubblewrap.md) |
| 0010 | [Keep comments out of niri's KDL, validate the built config](./adr/0010-niri-config-kdl.md) |
| 0011 | [Put MangoHud first in the Vulkan layer chain](./adr/0011-mangohud-first-vulkan-layer.md) |
| 0012 | [Size the streamed output from what the client reports](./adr/0012-size-output-from-client-reports.md) |
| 0013 | [Disarm on client disconnect, and never leave niri without an output](./adr/0013-disarm-on-client-disconnect.md) |
| 0014 | [Re-announce Steam's virtual gamepads when Steam lists them](./adr/0014-reannounce-steam-virtual-gamepads.md) |
| 0015 | [Stream audio through a positioned sink, chosen per client](./adr/0015-positioned-sink-for-stream-audio.md) |
| 0016 | [Hold the performance power profile for a VR session's lifetime, event-driven](./adr/0016-performance-power-profile-during-vr.md) |
| 0017 | [Expose the M1 video decoder through VA-API, with avd-fw from master](./adr/0017-ali-mba-linux-avd-vaapi.md) |
| 0018 | [Build a fresh output each time the `steam` virtual output is turned off](./adr/0018-fresh-output-per-virtual-output-disable.md) |
| 0019 | [Show virtual outputs on physical monitors through projections](./adr/0019-virtual-output-projection.md) |
| 0020 | [Show virtual outputs in one overview band column](./adr/0020-virtual-output-overview-band.md) |
| 0021 | [Patch the Hetzner master in place, and keep calls on a separate edge node](./adr/0021-patch-hetzner-master-in-place.md) |
| 0022 | [Encrypt every Hetzner data volume, behind a restore-tested backup](./adr/0022-encrypt-hetzner-volumes.md) |
| 0023 | [Undervolt the RX 9070 XT to -40mV, not to the edge](./adr/0023-gpu-undervolt-margin.md) |
| 0024 | [Override amdgpu kernel parameters only with a measured reason](./adr/0024-amdgpu-kernel-parameters.md) |
| 0025 | [Start a Steam Link VR stream on desktop capture, end it when SteamVR exits](./adr/0025-steam-link-vr-stream-lifecycle.md) |
| 0026 | [Keep Hetzner worker nodes usable: dial kubelets by name, heal a stuck Cilium host datapath](./adr/0026-hetzner-worker-node-networking.md) |
| 0027 | [Add foveated rendering to D3D11 VR games by forking DXVK, behind an environment gate](./adr/0027-fork-dxvk-for-foveated-rendering.md) |
| 0028 | [Draw the cursor into the capture during a Steam Link VR stream](./adr/0028-draw-cursor-into-vr-stream-capture.md) |
| 0029 | [Retrieve memories and skill sections by embedding, behind an option](./adr/0029-embedding-retrieval-for-memory-and-skills.md) |
| 0030 | [Inject confident memories in full, and keep a names-only catalogue](./adr/0030-inject-confident-memories-and-use-a-catalogue.md) |
| 0031 | [Inject skill sections above a calibrated floor, and trial both hooks with a log](./adr/0031-skill-hook-with-a-calibrated-floor-and-a-trial-log.md) |
| 0032 | [Fail closed, index on a separate server, ship telemetry to Loki and Tempo](./adr/0032-fail-closed-separate-index-server-and-telemetry.md) |
| 0033 | [Route more work to cheap delegates; Haiku 5.5 first on Copilot](./adr/0033-route-more-work-to-cheap-delegates.md) |
| 0034 | [Run the observability stack as one pod with `podman kube play`](./adr/0034-observability-pod-via-podman-kube-play.md) |
| 0035 | [Report the observability stack's disk budget instead of enforcing it](./adr/0035-disk-budget-reported-not-enforced.md) |
| 0037 | [Review token use weekly in two tiers, unattended](./adr/0037-two-tier-unattended-token-review.md) |
| 0038 | [Shorten the skill listing at install, and cap injected tokens](./adr/0038-shorten-the-skill-listing-at-install-and-cap-injected-tokens.md) |
| 0039 | [Do not add more retrieval machinery to the memory hook](./adr/0039-do-not-add-more-retrieval-machinery-to-the-memory-hook.md) |
| 0040 | [Keep control-centre state in SQLite, judge liveness by process identity, and drive it from events](./adr/0040-control-centre-store-liveness-event-feed.md) |
| 0041 | [Build the control centre in claude-monitor and couple loosely to cortexiphan](./adr/0041-control-centre-code-home-cortexiphan-coupling.md) |
| 0042 | [Run the control-centre web view as a user service on every machine](./adr/0042-run-the-control-centre-web-view-as-a-user-service-everywhere.md) |
| 0043 | [Share Rust compilation through sccache and sweep stale target directories](./adr/0043-rust-build-cache.md) |
| 0044 | [Run the PR check's sections in parallel, one eval per output set](./adr/0044-parallel-pr-check.md) |
| 0045 | [Keep an extra fast keyslot on the home LUKS volumes](./adr/0045-keep-an-extra-fast-keyslot-on-the-home-luks-volumes.md) |
| 0046 | [Trace delegated agy calls from the wrapper, as children of Claude's tool span](./adr/0046-trace-delegated-agy-calls-from-the-wrapper.md) |
| 0047 | [Load the shared skills in agy through a declared skills.json](./adr/0047-load-shared-skills-in-agy-through-a-declared-skills-json.md) |
| 0048 | [Route agy's work to Flash through a pinned subagent, and enforce it with an orchestrator](./adr/0048-route-agy-work-to-flash-through-a-pinned-subagent.md) |
| 0049 | [Select the pm backend on every call](./adr/0049-select-the-pm-backend-on-every-call.md) |
| 0050 | [Plan time from pm output and write an ics file](./adr/0050-plan-time-from-pm-output-into-ics.md) |
| 0051 | [Register, time-box and probe every pin](./adr/0051-register-time-box-and-probe-every-pin.md) |
| 0052 | [Treat a store's first readiness answer as a probe artefact, not an outage](./adr/0052-readiness-counts-from-the-first-probe.md) |
| 0053 | [Tag game audio streams for OBS instead of routing them through a sink](./adr/0053-tag-game-audio-streams-for-obs.md) |
| 0054 | [Link desktop streams to an OBS sink by title, not by app](./adr/0054-link-desktop-streams-to-an-obs-sink-by-title.md) |
| 0055 | [Hide user-typed and unused skills from the model's listing](./adr/0055-hide-user-typed-and-unused-skills-from-the-listing.md) |

## Design specs and plans

### Specifications

- [Steam Remote Play host on ali-desktop - design](./superpowers/specs/2026-08-24-steam-streaming-design.md)
- [Streaming to a niri virtual output - design](./superpowers/specs/2026-08-25-niri-virtual-output-streaming-design.md)
- [Remote Play input routing through extest - design](./superpowers/specs/2026-09-23-remote-play-input-routing-design.md)
- [Remote Play game mode: stream-aware launches](./superpowers/specs/2026-09-24-remote-play-game-mode-design.md)
- [Project management skill: design](./superpowers/specs/2026-10-21-project-management-skill-design.md)
- [time-management skill design](./superpowers/specs/2026-10-21-time-management-skill-design.md)

### Plans

- [Steam Remote Play probe log - ali-desktop](./superpowers/plans/2026-08-24-steam-streaming-probes.md)
- [Steam Remote Play Host Streaming Implementation Plan](./superpowers/plans/2026-08-24-steam-streaming.md)
- [stream-mode: compositor backends beyond niri](./superpowers/plans/2026-08-27-stream-mode-compositor-backends.md)
- [Project management skill Implementation Plan](./superpowers/plans/2026-10-21-project-management-skill.md)

## Token efficiency

- [Token efficiency reviews](./token-efficiency/README.md)

### Decisions

- [0001: Subagent default tier](./token-efficiency/decisions/0001-subagent-default-tier.md)
- [0002: Autocompact 350k](./token-efficiency/decisions/0002-autocompact-350k.md)
- [0003: Fixed context trim](./token-efficiency/decisions/0003-fixed-context-trim.md)
- [0004: Ranged reads](./token-efficiency/decisions/0004-ranged-reads.md)
- [0005: Script candidates dismissed](./token-efficiency/decisions/0005-script-candidates-dismissed.md)

### Reviews

- [2026-10-25 ali-desktop](./token-efficiency/reviews/2026-10-25-ali-desktop.md)
