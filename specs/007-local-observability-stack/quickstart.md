# Quickstart: validating the stack end to end

Run per OS (Linux: `ali-desktop`; macOS: `ali-work-laptop-macos`). Contracts:
[module options](contracts/module-options.md), [cc-obs-query CLI](contracts/cc-obs-query.md),
[cc-obs-ledger](contracts/cc-obs-ledger.md), [review formats](contracts/review-formats.md).
Times are ISO 8601 UTC; record command output as evidence (constitution II).

## 0. Pure checks (CI-safe, no containers)

1. `just check` — includes `observability-stack-tests`: rendered pod and store configs
   (pinned digests, loopback ports, retention, datasources), Linux and darwin evaluation.
2. `cargo fmt --check && cargo clippy -- -D warnings && cargo test` in `scripts/token-tools`.
3. Expected: all green. Negative tests must fail when a digest is removed or a port is bound to `0.0.0.0`.

## 1. Bring-up (story 1, SC-001, SC-015)

1. Enable `modules.observabilityStack.enable` on the host; `just switch`.
2. Within 10 minutes: `cc-obs-query health` reports loki, tempo, prometheus, grafana, collector ok.
3. Open Grafana on `http://127.0.0.1:3000`; Connections → Data sources → all three "healthy".
4. Reboot (or log out and in): re-run `cc-obs-query health` with no manual action.
5. Disable the option, switch: `podman ps` shows no stack containers.
6. Suspend and resume the machine (macOS: close the lid or sleep it): after waking, `cc-obs-query health` reports all components ok without manual action, and a query for data from before the suspend still returns it.
7. Probe exposure: `ss -ltn | grep -E ':(3000|3100|3200|9090|4317|4318)'` shows only `127.0.0.1`.

## 2. Claude Code telemetry (story 2, SC-002, SC-005)

1. Start a session, run one prompt that calls a tool and a skill.
2. Within 1 minute: Grafana Explore → Tempo shows an `interaction` trace with `llm_request` and `tool` spans; Loki shows `tool_result` events for the `session.id`; Prometheus has the token-usage series (exact Prometheus name recorded in T032).
3. Stop the stack, run Claude Code: no error, no added delay (compare `time` of a fixed prompt, SC-005).
4. Canary check: put `CANARY-7f3a` in a prompt; confirm it is nowhere in Loki, Tempo or Prometheus (default gates off).

## 3. Token attribution (story 3, SC-006, SC-007)

1. After a day of use: `cc-obs-query top tool --since 1d`, `cc-obs-query top skill`, `cc-obs-query top mcp`, `cc-obs-query top fixed`.
2. Sum of category tokens is within 5% of the per-session totals reported by Claude Code.
3. `cc-obs-query session <id>` shows context per turn and cache hit ratio; gaps appear as `unavailable`, not `0`.

## 4. Recall (story 5, SC-003, SC-004)

1. Submit a prompt that triggers recall; find the recall record (Loki) and metrics.
2. Stop the embedding server, submit another prompt: a failed record with cause is visible.
3. From the recall record, reach the Claude Code trace in ≤ 2 clicks via `session.id`.

## 5. Review workflow (story 4, SC-009, SC-010)

1. `cc-obs-query digest --since 7d` completes and writes a digest ≤ 32 KiB.
2. Scheduled run (set `review.schedule` to a near time): stage 1 then stage 2 run unattended, spend within `review.maxBudgetUSD`, findings land in the state dir; kill the machine mid-run and confirm the next run covers the missed period.
3. Promote one finding to a decision record; run a second review and see its before/after.

## 6. Disk bound and retention (SC-014)

1. Lower `maxDiskGB` to a small value on a scratch data dir; generate load; confirm the guard writes `guard.json` as `over`, sends one notification, leaves the collector running, and returns to `ok` under 90%.
2. After 30 days (or with `retentionDays = 1` and a day's wait) older data is gone and newer remains.

## 7. MCP versus CLI experiment (S4, FR-038, SC-011)

1. Build the query core once; wrap as `cc-obs-query` (CLI + skill text) and as an MCP stdio server.
2. Five representative tasks, three runs each, fresh session per run, same prompts, same
   backend data. Record per run: idle context tokens at start, total input/output tokens,
   tool-result tokens, calls and retries, success against a scripted ground truth, wall clock,
   permission prompts, transport failures. Include a CLI arm without concise defaults to
   isolate output design.
3. Decide by FR-039: within 10% on tokens per task, the lower idle cost and simpler maintenance wins. Record in a decision record and an ADR; delete the loser.
