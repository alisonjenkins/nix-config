# Subsystem pointers

Where each subsystem's code, docs and decisions live. `CLAUDE.md` carries a one-line index; the detail is here so it is read only when the work touches that subsystem.

## Minecraft modpack server packaging

Lives in the **`minecraft-modpack-packaging`** skill (`.claude/skills/minecraft-modpack-packaging/SKILL.md`) — `create-sky-colonies-server` (vanilla) + `create-arkana-aeronautics-server` (manifest+bisection) patterns, the bisect loop, mod-version bumping (`find-mod-bumps`), composition files, crash triage. Auto-loads when working on `pkgs/create-*-server` / `pkgs/minecraft-modpack-tools`.

## Beat Saber mod install

Lives in the **`beatsaber-modding`** skill (`.claude/skills/beatsaber-modding/SKILL.md`) — `pkgs/beatsaber-mods` (BeatMods-resolved mod payload) + `home/modules/beatsaber` (merge-copy placement + `beatsaber-patch-mods`), how to add/remove a mod, bump the pinned game version, and debug BSIPA/install issues. Auto-loads when working on `pkgs/beatsaber-mods` / `home/modules/beatsaber`.

## Helldivers 2 modding

Lives in the **`helldivers2-modding`** skill (`.claude/skills/helldivers2-modding/SKILL.md`) — `pkgs/arsenal` (Linux-native GUI mod manager, migrated from the deprecated/buggy h2mm-cli, since removed) + `pkgs/hd2-repatcher` + `home/modules/helldivers2-mods` (steamLibraryRoots lookup, warning-only; mod install/enable itself stays manual, see the skill for why), how to install a mod, the h2mm-cli deployment-bug incident writeup, and bumping pinned versions. Auto-loads when working on `pkgs/arsenal` / `pkgs/hd2-repatcher` / `home/modules/helldivers2-mods`.

## Memory and skill retrieval

`modules.memoryRecall` (`home/modules/memory-recall`, off by default) injects the memories closest to each prompt (snippets from 0.68, whole memory from 0.74) via a local EmbeddingGemma 2 server; `memory-recall catalogue` makes the names-only index that can replace `MEMORY.md`. Code in `scripts/retrieval-eval` (`pkgs.memory-recall`); how it works, how to enable it and the benchmark results: `docs/memory-recall.md`, ADRs 0029 and 0030. Needs `pkgs.llama-cpp-upstream` (nixpkgs' llama.cpp lacks the `gemma-embedding2` architecture).

## AI control centre

`claude-monitor` (separate Rust repo, Home Manager module `programs.claude-monitor`, all options off by default) is the overview and persistence layer for Claude Code and Copilot sessions: states, survive-reboot respawn in the right worktree (`restore`, never automatic), plan progress, cortexiphan export, optional loopback web view. How to enable it, what it installs, state and log locations, recovery: `docs/ai-control-centre.md`; ADRs 0040 and 0041; design in `specs/008-ai-control-centre/`.

## Observability stack

`modules.observabilityStack` (`home/modules/observability-stack`, off by default) runs Loki, Tempo, Prometheus, Grafana and an OTel collector as one podman pod (systemd user service on Linux, launchd agent on macOS) and points Claude Code's telemetry at it, to find where tokens go. Code in `scripts/token-tools` (`cc-obs-ledger` hook tool, `cc-obs-query` CLI). How to use it, the privacy gates and checks: `docs/observability-stack.md`, ADRs 0034 and 0035, design in `specs/007-local-observability-stack/`. The weekly two-tier token review (`review.enable`, runner `observability-stack-review`, timer or launchd interval; ADR 0037) is built and tested against fakes; the first real review (T061) is still manual.

## Rust build cache

`modules.rustBuildCache` (`home/modules/rust-build-cache`, on by default for `modules.desktop` hosts) sets sccache as the cargo rustc wrapper and runs a daily `cargo-sweep` over `~/git` (targets unused for 1 day) so worktrees stop filling `/home`. Why and the measurements: ADR 0043.
