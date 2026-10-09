---

description: "Task list for the local observability stack"
---

# Tasks: Local Observability Stack

**Input**: Design documents from `/specs/007-local-observability-stack/`

**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md)

**Tests**: INCLUDED. Constitution II makes failing-test-first mandatory where behaviour is testable. Runtime behaviour on a real podman machine cannot run in CI; those steps are manual quickstart tasks and are named as such.

**Organization**: grouped by user story so each can be built and checked on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1 to US7, matching `spec.md`
- Paths are repository-relative.

## Working rules (apply to every task)

- One task is one commit unless a task says otherwise; each commit must build alone (constitution I). Run the `git` skill before committing. No AI attribution lines.
- Before writing code, invoke the `programming` skill and read its language file (Nix or Rust); before tests, the `testing` skill.
- `git add` new files before any `nix build`/`just check` (flake sources only see tracked files).
- Rust: `cargo fmt --check`, `cargo clippy -- -D warnings`, no `unwrap`/`expect` outside tests (constitution IV). Shell inside Nix resolves tools from Nix.
- Red, then green, locally: write the failing test first and see it fail, then implement. The test and the change that makes it pass land in one commit (or the check is registered only in the commit that turns it green), so no commit leaves `just check` red (constitution I and II). Each test task below is committed together with the implementation task that satisfies it. Quote command output as evidence when closing a task.
- Times in files and logs are ISO 8601 UTC.

---

## Phase 1: Setup

**Purpose**: empty, building scaffolding. Nothing here changes behaviour.

- [X] T001 Create the module skeleton `home/modules/observability-stack/default.nix` with only `options.modules.observabilityStack.enable` and an empty `config = mkIf cfg.enable {}`, and export it as `observability-stack` in `flake-modules/home-modules.nix`
- [X] T002 [P] Create the Rust workspace `scripts/token-tools/Cargo.toml` with empty crates `cc-obs-ledger` (bin) and `cc-obs-query` (lib + bin), each with a trivial passing test, rust-toolchain settings matching `scripts/retrieval-eval`
- [X] T003 [P] Package the workspace in `pkgs/token-tools/default.nix` (both binaries, `cargo test` in checkPhase) and register it as `token-tools = pkgs.callPackage ./token-tools {};` in `pkgs/default.nix`, plus `token-tools = (pkgsFor system).token-tools;` in `flake-modules/packages.nix` so CI builds it
- [X] T004 [P] Create `docs/token-efficiency/README.md` describing the `reviews/` and `decisions/` folders and linking `contracts/review-formats.md`

**Checkpoint**: `just check` passes; the module exists but does nothing.

---

## Phase 2: Foundational (spikes that unblock every story)

**Purpose**: close the unconfirmed items in `research.md` before anything depends on them. Record each result in `research.md` under a "Spike results" heading with date, command and output. S4 (MCP versus CLI) is in Phase 6 because it needs the query core.

- [ ] T005 Spike S1: on `ali-work-laptop-macos` run a two-container pod with `podman kube play` on a `podman machine`; confirm bind-mount paths under `~/Library/Application Support`, `--replace`, restart after VM reboot, and loopback-only publishing. Manual. If it fails, record the fallback decision (native nixpkgs services on macOS) before continuing
- [X] T006 [P] Spike S2: on `ali-desktop` run the pinned Loki and Tempo images with `podman`; confirm Tempo's retention key name, Tempo's OTLP receiver on non-default ports, and Loki's OTLP ingest endpoint; save the working minimal configs under `specs/007-local-observability-stack/spike-configs/`. Also confirm Prometheus' OTLP receiver can promote the resource attributes `host`, `review.run` and `repository` to labels (config key and version), since the review self-exclusion and per-project views depend on it
- [X] T007 [P] Spike S3: read a real Claude Code transcript and hook payloads; confirm the `usage` field names, whether `agent_id`/`prompt_id` appear, and the join key between telemetry events and spans; save a redacted fixture under `scripts/token-tools/cc-obs-ledger/tests/fixtures/`
- [X] T008 [P] Spike S5: run `claude -p --max-budget-usd 0.05 --model haiku` unattended from a timer-like environment; record what happens at the ceiling (exit code, partial output) and that user-level settings apply. Also find how to run the review stages without the memory-recall and `cc-obs-ledger` hooks and without the project instruction files while keeping the owner's auth: `claude --bare` skips hooks but reads only an API key or `apiKeyHelper` (not OAuth or the keychain), so test `--bare`, `--setting-sources` and `--settings` and record which combination works. Record how to set `OTEL_RESOURCE_ATTRIBUTES=review.run=1` for those runs
- [X] T009 Fetch the image digests for grafana, loki, tempo, prometheus and otel-collector-contrib at the tags in `research.md` (R6) and record them in a pure Nix file `home/modules/observability-stack/images.nix` (tag plus `@sha256:` digest)

**Checkpoint**: every item the plan marked unconfirmed is confirmed or has a recorded fallback.

---

## Phase 3: User Story 1 - Bring up the stack on either OS (Priority: P1) MVP

**Goal**: one option gives a working Loki, Tempo, Prometheus, Grafana and collector in containers on Linux and macOS.

**Independent Test**: `quickstart.md` sections 0, 1 and 6 on one host per OS.

### Tests for US1 (write first, watch fail; commit each with the task that satisfies it)

- [X] T010 [P] [US1] Create `flake-modules/observability-stack-tests.nix` (pattern of `flake-modules/obs-config-tests.nix`) with a check asserting every rendered image is pinned by digest and none uses `latest`; and that the pod sets the image pull policy to pull only when missing, so already-pulled images keep running offline
- [X] T011 [P] [US1] In the same file add a check asserting every published port binds `127.0.0.1` by default and that setting a wider `listenAddress` without `exposeBeyondLoopback` fails evaluation with a message naming the option
- [X] T012 [P] [US1] Add a check asserting retention is 30 days in the Loki, Tempo and Prometheus configs, Prometheus gets a size limit from the budget split, and a split summing over 90% of `maxDiskGB` (headroom for Grafana state and the collector queue) fails evaluation; and that the Prometheus config promotes the resource attributes `host`, `review.run` and `repository` to labels
- [X] T013 [P] [US1] Add a check evaluating a Linux home configuration and a darwin home configuration with the module on, asserting the Linux one has the systemd user service and the darwin one the launchd agent and no systemd unit; plus that the rendered ports, published-port list and Grafana datasource provisioning are byte-identical across the two (story 1 scenario 4)
- [X] T014 [P] [US1] Add hermetic bats tests `home/modules/observability-stack/tests/disk-guard.bats` for the guard logic: under budget writes `ok`, over budget writes `over` without ever stopping the collector and notifies once per 24 h, back under 90% returns to `ok` (podman, notify-send and osascript replaced by stubs), and for the runner start check: a port already bound makes start fail with a message naming the port and the `ports.*` option to change (bind check stubbed)

### Implementation for US1

- [X] T015 [US1] Implement all options from `contracts/module-options.md` and their assertions (budget sum, duplicate ports, known-used ports 8080/8110/9100, loopback rule, NixOS needs `modules.podman`, image pinning) in `home/modules/observability-stack/default.nix`. Also write `$XDG_CONFIG_HOME/cc-obs/endpoints.json` (ports and listen address, the single source for `cc-obs-query` and `cc-obs-ledger`; env `CC_OBS_ENDPOINTS` overrides) through `home.file`, so interactive sessions and the review runner read the same endpoints
- [X] T016 [P] [US1] Render Loki and Tempo configs (retention, filesystem storage, Tempo OTLP on internal non-default ports, Loki OTLP ingest) in `home/modules/observability-stack/configs.nix`
- [X] T017 [P] [US1] Render Prometheus (retention flags, OTLP receiver, self-scrape) and the collector pipelines (OTLP in; logs to Loki, traces to Tempo, metrics to Prometheus; host label) in `home/modules/observability-stack/collector.nix`. Include the OTLP resource-attribute promotion for `host`, `review.run` and `repository`
- [X] T018 [P] [US1] Render Grafana provisioning (three datasources with trace-to-logs and trace-to-metrics links, dashboards provider, anonymous admin on loopback) in `home/modules/observability-stack/grafana.nix`
- [X] T019 [US1] Render the pod YAML (five containers, shared network, published ports on `listenAddress`, read-only config mounts, data bind mounts) in `home/modules/observability-stack/pod.nix`. Set the image pull policy to pull only when missing
- [X] T020 [US1] Implement the disk guard script and its package in `home/modules/observability-stack/disk-guard.nix` until T014 passes
- [X] T021 [P] [US1] Implement the Linux runner (systemd user service running `podman kube play`, restart on failure, start at login, guard timer, clear error naming a missing runtime, and a pre-start check that fails naming the port and option if a configured port is already bound) in `home/modules/observability-stack/runner-linux.nix`
- [X] T022 [P] [US1] Implement the macOS runner (launchd agent that ensures the podman machine is initialised and started, runs `podman kube play --replace`, guard interval, clear error naming a missing runtime, and the same pre-start port check) in `home/modules/observability-stack/runner-darwin.nix`
- [X] T023 [US1] Wire the module into `default.nix` so it imports the renderers and the correct runner per platform; run T010 to T013 until green
- [ ] T024 [US1] Enable the module on `ali-desktop` (`home/machines/ali-desktop/default.nix`) and on `ali-work-laptop-macos` (home-manager user block in `flake-modules/hosts/ali-work-laptop-macos/default.nix`), keeping `modules.podman.enable` on the Linux host (Status 2026-10-09: ali-desktop done, including `modules.podman` with docker compat off; the macOS host waits for spike T005, which decides the podman machine setup.)
- [X] T025 [US1] Write ADR `docs/adr/0034-observability-pod-via-podman-kube-play.md` (why one pod definition for both OSes, alternatives from R1) and add it to `docs/adr/README.md`
- [X] T026 [US1] Write ADR `docs/adr/0035-disk-budget-reported-not-enforced.md` (why the guard reports the disk budget instead of halting the collector; not filesystem quotas or deleting store blocks) and add it to `docs/adr/README.md`
- [ ] T027 [US1] Manual: run `quickstart.md` sections 0, 1 and 6 on `ali-desktop`, then on `ali-work-laptop-macos`; save output as `specs/007-local-observability-stack/evidence/us1-<host>.md`. Also suspend and resume the machine (macOS: sleep the laptop) and confirm the services come back and the stored data still queries

**Checkpoint**: SC-001, SC-014 (disk), SC-015 verified on both OS families.

---

## Phase 4: User Story 2 - See Claude Code sessions as traces and logs (Priority: P1)

**Goal**: every Claude Code session lands in the stack with no per-session setup, and nothing sensitive is stored by default.

**Independent Test**: `quickstart.md` section 2.

- [X] T028 [P] [US2] Add a check in `flake-modules/observability-stack-tests.nix` asserting the rendered Claude user settings carry the telemetry env pointing at the configured collector port and that `OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_DETAILS` and `OTEL_LOG_TOOL_CONTENT` are absent by default and present only when their options are on; also asserting `OTEL_METRICS_INCLUDE_REPOSITORY=1` is present while `claudeCode.includeRepository` is on (the default)
- [X] T029 [P] [US2] Add a bats test `home/modules/observability-stack/tests/collector-redaction.bats` feeding sample OTLP JSON with prompt text, `tool_parameters` and `tool_input` through the rendered collector processors (using the collector's offline validation or a stubbed pipeline) and asserting they are dropped unless the matching option is on
- [X] T030 [US2] Add redaction processors (drop prompt, tool parameter, tool input and content attributes unless the options allow) to `home/modules/observability-stack/collector.nix`
- [X] T031 [US2] Write the telemetry `env` and `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA` into the user-level settings through the existing `programs.claude-code.settings.env` merge in `home/modules/observability-stack/default.nix`, honouring `claudeCode.*` options; confirm the activation merge in `home/programs/claude-code/default.nix` still produces valid settings. Include `OTEL_METRICS_INCLUDE_REPOSITORY` driven by `claudeCode.includeRepository` so token metrics carry the project
- [ ] T032 [US2] Manual: run `quickstart.md` section 2 on `ali-desktop` (trace and logs within 1 minute, stack-down run unaffected, canary absent) and save evidence to `specs/007-local-observability-stack/evidence/us2.md`; repeat on macOS. Also confirm the repository attribute appears on the token metric (name or hash?) and record the exact Prometheus metric names, since the quickstart uses a placeholder

**Checkpoint**: SC-002 and SC-005 verified; content gates confirmed off.

---

## Phase 5: User Story 3 - Find where tokens are spent (Priority: P1)

**Goal**: token spend is attributable by tool, skill, MCP server, sub-agent, memory and fixed context, with gaps shown as unavailable.

**Independent Test**: `quickstart.md` section 3.

### Tests for US3 (write first; commit each with the task that satisfies it)

- [X] T033 [P] [US3] Write `cc-obs-ledger` parser tests in `scripts/token-tools/cc-obs-ledger/tests/transcript.rs` against the T007 fixture: per-request usage, context size per turn, cache hit ratio, malformed lines skipped with a counted warning; plus one `cc_obs_ledger.tool_call` record per tool call carrying `input_hash`, `input_prefix_hash`, `input_bytes` and `result_bytes`
- [X] T034 [P] [US3] Write privacy tests in `scripts/token-tools/cc-obs-ledger/tests/privacy.rs`: a transcript containing a canary string produces payloads that never contain it, and neither does any tool input text; the same input gives the same `input_hash` under one key and a different one under another key; and that records carry the resource attributes from `OTEL_RESOURCE_ATTRIBUTES` (for example `review.run=1`)
- [X] T035 [P] [US3] Write census tests in `scripts/token-tools/cc-obs-ledger/tests/census.rs` with a fixture directory of instruction files, skill listing and MCP definitions, asserting per-component token estimates and that the census prints nothing to stdout

### Implementation for US3

- [X] T036 [US3] Implement the transcript reader and metric computation in `scripts/token-tools/cc-obs-ledger/src/transcript.rs` until T033 passes, and the keyed tool-call hashing in `src/toolcalls.rs` (per-host HMAC key created on first run in `$XDG_STATE_HOME/cc-obs-ledger/hmac.key`, mode 0600, outside the Nix store) until T033 and T034 pass
- [X] T037 [US3] Implement the census in `scripts/token-tools/cc-obs-ledger/src/census.rs` until T035 passes
- [X] T038 [US3] Implement the detached best-effort OTLP/HTTP sender (3 s timeout, local error log, exit 0) in `scripts/token-tools/cc-obs-ledger/src/send.rs`, and the `census`/`turn`/`end` subcommands in `src/main.rs` per `contracts/cc-obs-ledger.md`, until T034 passes. Read endpoints from `endpoints.json` (see T015). The sender is deliberately kept separate from the one in `scripts/retrieval-eval` (that package builds from its own source directory; a shared crate would change its source boundary): about 100 lines, no new dependency, revisit at a third user
- [X] T039 [US3] Add the SessionStart, Stop and SessionEnd hook entries (gated by `ledger.enable`) in `home/modules/observability-stack/default.nix`, and a check asserting they are present and never write to stdout
- [X] T040 [P] [US3] Render recording rules from the `prices` option (cost estimate per category, labelled as estimates) into the Prometheus config in `home/modules/observability-stack/collector.nix`, with a check that changing a price changes the rule
- [X] T041 [US3] Add the token-cost dashboard `home/modules/observability-stack/dashboards/token-cost.json` (totals by session, project (the `repository` attribute, else the ledger working-directory label), model, tool, skill, MCP server, sub-agent, memory, fixed context; context per turn; cache hit; "unavailable" panels for gaps; before/after comparison variable) and extend the provisioning check to validate it is valid JSON and loaded. Every panel is computed from retained data only (spec FR-026)
- [ ] T042 [US3] Manual: run `quickstart.md` section 3 after a day of use; verify category sums are within 5% of Claude Code's per-session totals (SC-007) and save evidence to `specs/007-local-observability-stack/evidence/us3.md`

**Checkpoint**: SC-006 and SC-007 verifiable from the dashboard.

---

## Phase 6: User Story 4 - Regular review that turns data into decisions (Priority: P1)

**Goal**: a weekly unattended two-tier review produces ranked findings; the owner records decisions; later reviews measure them.

**Independent Test**: `quickstart.md` section 5 plus section 7.

### Tests for US4 (write first; commit each with the task that satisfies it)

- [X] T043 [P] [US4] Record fixture responses for Prometheus, Loki and Tempo queries in `scripts/token-tools/cc-obs-query/tests/fixtures/` and write command tests in `tests/commands.rs` for `top`, `tool`, `session`, `repeats`, `recall`, `health` asserting JSON shape, `--limit`, `unavailable` instead of zero, and the structured error object
- [X] T044 [P] [US4] Write bounded-output tests in `scripts/token-tools/cc-obs-query/tests/bounds.rs`: default `--max-bytes` truncates with the `truncated`/`next` marker, digest stays under 32 KiB, no fixture content beyond references appears; and `digest --write` rejects an oversize digest, a content-like field, and a cited evidence reference that does not exist
- [X] T045 [P] [US4] Write pack tests in `scripts/token-tools/cc-obs-query/tests/pack.rs` for loading `docs/token-efficiency/questions.yaml`: unknown signal rejected, `unused-signals` lists a collected signal that no question uses, `retire:` honoured, regrowth rule suppresses a dismissed finding below 1.5x
- [X] T046 [P] [US4] Write runner tests `home/modules/observability-stack/tests/review-runner.bats` with a stub `claude`: stage 1 then stage 2 run in order with the configured models and `--max-budget-usd`, a nonzero exit at the ceiling leaves a visible failure record, a missed period is detected and covered next run, nothing is written inside the repository; when stage 1 fails or hits its budget the runner falls back to `cc-obs-query digest --baseline` and the digest is marked `stage1: baseline`; and that each stage is started with `OTEL_RESOURCE_ATTRIBUTES` containing `review.run=1`

### Implementation for US4

- [X] T047 [US4] Implement, as a library API that the CLI and the S4 adapter both wrap, the backend clients (Prometheus, Loki, Tempo) and bounded-output layer in `scripts/token-tools/cc-obs-query/src/{backend,bounds}.rs`, reading endpoints from `$XDG_CONFIG_HOME/cc-obs/endpoints.json` (env `CC_OBS_ENDPOINTS` overrides)
- [X] T048 [US4] Implement `top`, `tool`, `session`, `recall`, `health` in `scripts/token-tools/cc-obs-query/src/commands/` until T043 passes for them
- [X] T049 [US4] Implement `repeats` from the `cc_obs_ledger.tool_call` records, never from tool input content (equal `input_hash` within a session for identical calls, equal `input_prefix_hash` for near-identical ones, a large `result_bytes` followed by a narrower call to the same tool, repeated call sequences) in `scripts/token-tools/cc-obs-query/src/commands/repeats.rs`
- [X] T050 [US4] Implement the pack loader, `unused-signals` and `compare` in `scripts/token-tools/cc-obs-query/src/{pack,commands/compare}.rs` until T045 passes
- [X] T051 [US4] Make `top`, `tool`, `session`, `repeats` and `recall` exclude data labelled `review.run=1` by default (flag `--include-review` to include it) and report that excluded spend as the review's own cost, with the test written first in `scripts/token-tools/cc-obs-query/tests/exclude_review.rs`
- [X] T052 [US4] Implement `digest --baseline` (mechanical run of the pack with no model) and `digest --write <file>` (validate a model-gathered digest: schema, size cap, no content-like fields, evidence references exist), both with prior-decision before/after, dismissed suppression and the own-cost field, in `scripts/token-tools/cc-obs-query/src/commands/digest.rs` until T044 passes
- [X] T053 [US4] Write the starting question pack `docs/token-efficiency/questions.yaml` (ten questions from `contracts/review-formats.md`) and a check that it parses and references only collected signals; the `repeat-calls` question lists `cc_obs_ledger.tool_call` as its signal
- [ ] T054 [US4] Spike S4: wrap the query core once as a throwaway MCP stdio adapter in `scripts/token-tools/cc-obs-query/examples/mcp_adapter.rs` and run the experiment from `quickstart.md` section 7 (five tasks, three runs, both arms plus the no-concise-defaults arm); save raw results and the comparison table in `specs/007-local-observability-stack/evidence/s4-mcp-vs-cli.md`. Runs after T047 to T053 (the query library) and before T056 (the review runner)
- [ ] T055 [US4] Record the S4 decision per FR-039: write ADR `docs/adr/0036-observability-tools-delivery-mechanism.md`, delete the losing adapter, and note the result in `research.md` R8
- [ ] T056 [US4] Implement the review runner (stage 1: the low-cost model runs the pack's `cc-obs-query` commands plus at most 3 drill-downs per question and submits via `digest --write`, falling back to `digest --baseline`; stage 2: the analysis model reads only the digest; `--max-budget-usd` per stage, state dir, failure and missed-run records). Each stage runs with `OTEL_RESOURCE_ATTRIBUTES=review.run=1` and with hooks and project instructions off in the way T008 found, and the runner reads each stage's reported cost from `claude -p --output-format json` into the digest's `own_cost` (spec FR-037). Implemented in `home/modules/observability-stack/review.nix` until T046 passes
- [X] T057 [US4] Add the `cc-obs-ledger notice` subcommand (prints one short line, for example "token review ready: <date>", only when the newest findings file in `review.stateDir` has not been promoted or dismissed; prints nothing otherwise, and never fails) in `scripts/token-tools/cc-obs-ledger/src/notice.rs`, with its test written first in `tests/notice.rs`, and a SessionStart hook entry gated by `review.notify` (default true) in `home/modules/observability-stack/default.nix` (spec FR-031)
- [X] T058 [US4] Write ADR `docs/adr/0037-two-tier-unattended-token-review.md` (why two tiers, the baseline fallback, per-stage spend ceilings, state directory instead of committing, how review runs are kept out of the data they analyse) and add it to `docs/adr/README.md`
- [ ] T059 [P] [US4] Add the schedule: systemd user timer in `home/modules/observability-stack/runner-linux.nix` and launchd calendar interval in `home/modules/observability-stack/runner-darwin.nix`, gated by `review.enable`, plus a check on both platforms
- [X] T060 [P] [US4] Add templates for the findings file and the decision record to `docs/token-efficiency/README.md` matching `contracts/review-formats.md`
- [ ] T061 [US4] Manual: run the first review by hand on `ali-desktop` after a week of data, promote findings, record at least one decision record in `docs/token-efficiency/decisions/`, run a second review and confirm it shows that decision's status; save evidence to `specs/007-local-observability-stack/evidence/us4.md` (SC-008, SC-009, SC-010). Also confirm that usage of the chosen tool (CLI calls or MCP tool calls) shows up in the tool and cost views (spec FR-045)

**Checkpoint**: SC-009 to SC-011 verifiable; first decisions recorded.

---

## Phase 7: User Story 5 - See memory and skill store activity (Priority: P2)

**Goal**: every recall (including empty and failed ones) is visible, measured, and joined to its Claude Code prompt.

**Independent Test**: `quickstart.md` section 4.

- [X] T062 [P] [US5] Add failing tests in `scripts/retrieval-eval/` (module of the existing telemetry tests) for: `session_id` taken from the hook payload and written to the log line and span, `outcome` of `success`/`empty`/`error` with `cause`, and metrics `recall_requests_total`, `recall_hits_total`, `recall_latency_seconds`, `recall_tokens_injected_total`; and that the log line, span and metrics carry the resource attributes from `OTEL_RESOURCE_ATTRIBUTES`
- [X] T063 [US5] Carry `session_id` and `outcome`/`cause` through `scripts/retrieval-eval/src/recall_log.rs` and `src/telemetry.rs` until the T062 tests pass
- [X] T064 [US5] Emit the four recall metrics over OTLP/HTTP from the existing detached `ship` path in `scripts/retrieval-eval/src/telemetry.rs` (best effort, no hook delay)
- [X] T065 [US5] When both modules are enabled, default `modules.memoryRecall.telemetry.lokiUrl` and `tempoEndpoint` to the stack's ports in `home/modules/observability-stack/default.nix`, with a check; leave explicit user values winning
- [X] T066 [P] [US5] Add a Grafana derived field on `session.id` linking the recall log line to the Claude Code trace, in `home/modules/observability-stack/grafana.nix`, with a provisioning check
- [ ] T067 [US5] Manual: run `quickstart.md` section 4 on `ali-desktop` (record visible, failure with cause when the embedder is stopped, two clicks to the trace) and save evidence to `specs/007-local-observability-stack/evidence/us5.md`

**Checkpoint**: SC-003 and SC-004 verified.

---

## Phase 8: User Story 6 - Ready-made dashboards and persistent history (Priority: P3)

**Goal**: the remaining dashboards exist on first switch; data survives restarts and expires on schedule.

**Independent Test**: `quickstart.md` section 6 retention steps after a day of use.

- [X] T068 [P] [US6] Add the Claude Code activity dashboard `home/modules/observability-stack/dashboards/claude-code.json` (sessions, tool latency, error rate, token and cost trends)
- [X] T069 [P] [US6] Add the recall dashboard `home/modules/observability-stack/dashboards/recall.json` (hit rate, score distribution, latency, failures, tokens injected)
- [X] T070 [P] [US6] Add the stack-health dashboard `home/modules/observability-stack/dashboards/stack-health.json` (store up/down, dropped data, disk budget exceeded, ingest rate, disk use against budget)
- [X] T071 [US6] Extend the provisioning check to assert all four dashboards load by UID and every datasource they reference exists
- [ ] T072 [US6] Manual: after a day of use confirm all dashboards populate, restart the stack and confirm yesterday's session is still queryable, and run the `retentionDays = 1` retention step; save evidence to `specs/007-local-observability-stack/evidence/us6.md`

**Checkpoint**: story 6 acceptance scenarios met.

---

## Phase 9: User Story 7 - Skill for review and tool design (Priority: P2)

**Goal**: a fresh session reviews token spend and designs a token-efficient tool by following a written method.

**Independent Test**: spec story 7 independent test (fresh session, five trials).

- [X] T073 [US7] Invoke the `skill-authoring` skill, then write `home/skills/token-efficiency/SKILL.md` (description line only in the always-loaded part) with `review.md` (question list, ranking, how to read each view, dismissal and regrowth rules) and `tool-design.md` (token-efficiency checklist from FR-041, delivery mechanism per ADR 0036, measurement plan). Mark any part not yet backed by a real review as provisional. No machine-specific paths or assumed tools
- [ ] T074 [US7] Trial the skill: five fresh sessions given only "review last week's token spend", plus two tool-design requests; record method adherence per trial and the checklist outcome in `specs/007-local-observability-stack/evidence/us7.md` (SC-012, SC-013 baseline). Also measure and record the skill's idle context cost (its description line in tokens) against the budget in spec FR-042
- [ ] T075 [US7] Update the skill from the trial results, the first real review (T061) and the S4 result (T055), removing the provisional marks that evidence now covers (FR-044)

**Checkpoint**: SC-012 met in at least 4 of 5 trials.

---

## Phase 10: Polish and cross-cutting

- [X] T076 [P] Write the topic doc `docs/observability-stack.md` (how to enable, ports, retention, privacy gates, review workflow, troubleshooting) and add one pointer line to `CLAUDE.md` under Key Systems
- [ ] T077 [P] Add the remaining ADR entries and index lines in `docs/adr/README.md` for decisions made during implementation (spike outcomes that changed the plan)
- [ ] T078 Run `prek run --all-files` and `just check`; fix findings in separate fixup commits against the commit they correct
- [ ] T079 Run `quickstart.md` end to end once more on `ali-desktop` and `ali-work-laptop-macos`; confirm SC-001 to SC-015 and save the final evidence index to `specs/007-local-observability-stack/evidence/README.md`
- [ ] T080 Confirm no secrets reached the Nix store or any log (grep rendered configs and the store paths of the pod), and that no file under `docs/token-efficiency/` contains prompt or file content

---

## Dependencies and execution order

- Phase 1 → Phase 2 → US1 (Phase 3). US1 blocks everything else.
- US2 needs US1. US3 needs US2 (collector routes) and T007. US4 needs US3 (data) and T008; within US4, T054–T055 (delivery decision) come after T047–T053 and before T056 (the review runner); its manual review T061 needs about a week of data collected since US2.
- US5 needs US1 and US2 (session id join); can run in parallel with US3/US4 once US2 is done.
- US6 needs the signals from US3 and US5. US7 needs T061 and T055.
- Within a story: tests, then implementation, then manual evidence. Start the data-collecting stack (T024) as early as possible, because T042, T061 and T072 need elapsed time, not effort.

## Parallel opportunities

- Phase 2: T006, T007, T008 together (T005 needs the macOS host).
- US1 tests T010 to T014 together; renderers T016, T017, T018 together; runners T021 and T022 together.
- US3 tests T033 to T035 together. US4 tests T043 to T046 together; T059 and T060 together.
- After US2: US3, US5 in parallel by different people or sessions (disjoint files: `scripts/token-tools/cc-obs-ledger` versus `scripts/retrieval-eval`).
- US6 dashboards T068 to T070 together.

## Implementation strategy

1. **MVP = Phase 1, 2 and US1 (T001 to T027)**: a reproducible stack on both OS families.
2. **Useful increment = + US2 and US3 (T028 to T042)**: Claude Code sessions visible and token spend attributable. Start collecting data here; it is the longest wait.
3. **Goal reached = + US4 (T043 to T061)**: the weekly review and decisions. This is the point of the feature.
4. Then US5, US7, US6 in that order, then Polish.
5. After each phase, stop at the checkpoint, run the named quickstart section, and only then continue.

## Notes

- Total: 80 tasks. Spikes (T005 to T008, T054) can change the plan; if one does, update `research.md` and `plan.md` in their own commit before dependent tasks.
- Manual tasks (T005, T027, T032, T042, T061, T067, T072, T079) need the owner's hosts; they are the named untestable glue under constitution II.
