# 0032. Fail closed, index on a separate server, ship telemetry to Loki and Tempo

- Status: Proposed. Built; on trial on `ali-desktop`.
- Date: 2026-10-08
- Amends [0029](0029-embedding-retrieval-for-memory-and-skills.md) and
  [0031](0031-skill-hook-with-a-calibrated-floor-and-a-trial-log.md).

## Context

Review of PR 521 asked for three changes to how the hooks behave in operation.

1. A prompt answered without the memories that hold its guard rails can make a bad
   mistake (such as deleting a production server), so the hook should fail or block
   rather than proceed bare. ADR 0029 had it fail open, and an interim change fell
   back to keyword matches.
2. New memories should be picked up without restarting the model, and `MEMORY.md`
   must not be allowed to grow, because it is loaded into every session.
3. The hook's behaviour should be observable in Loki and Tempo.

## Decision

- **Fail closed.** When a hook cannot retrieve memories or skills (the embedding
  server is unreachable after a 1.5 s retry, or the directory cannot be read) it
  exits 2 with a message, which blocks the prompt. `--on-unavailable keyword|allow`
  (module option `onUnavailable`) opts into BM25 matches or nothing. Prompts with
  nothing to retrieve pass: too short, nothing above the floor, and a fresh setup
  (no memories or skills yet, or the first index still running), so a new machine
  can prompt before it has anything to retrieve. Blocking applies only when there
  is something to retrieve and the server cannot be reached.
- **Index on its own server.** Each index run starts a short-lived
  `llama-server` on `indexPort`, indexes, and stops it. The query server is never
  restarted. `catalogue.enable` rewrites `MEMORY.md` as the names-only catalogue
  after each index run; it is off by default because it overwrites a file Claude
  maintains.
- **Telemetry through a detached shipper.** The hooks start `recall-ship`, which
  posts the log entry to Loki's push API and a two-span trace to Tempo's OTLP/HTTP
  endpoint, and the hook does not wait for it.

- **Correlate by session id.** Each log line and span carries Claude Code's
  `session_id` and `prompt_id` from the hook payload (`session.id`, `prompt.id` on
  spans). A valid `TRACEPARENT` in the environment, which Claude Code does not set
  for hooks today, makes the hook span continue that trace.

## Alternatives rejected

| Option | Why not |
|---|---|
| Keep failing open | A prompt can run without the memory that would have stopped it. |
| Keyword fallback as the default | It retrieves some memories, not the important one reliably; a blocked prompt is safer. Kept as an opt-in. |
| Restart the query server after each index | Needed because one long memory makes llama.cpp keep a 1.6 GB buffer (a full index, 2.7 GB), but it interrupts prompts. |
| Cap the compute buffer with a smaller `-ub` | `-ub 512` fails on long memories (ADR 0029). |
| Send telemetry from the hook process | A slow backend would delay every prompt, and the hook would wait on the network. |
| Add an OpenTelemetry SDK | Heavy dependencies for one span and one log line; OTLP/HTTP JSON is a small request. |
| Run Grafana Alloy to tail the log file | Another service to keep running, and no spans. |

## Consequences

- **Claude Code stops answering while the embedding server is down.** The message
  says why and how to relax it; the retry covers a server that is starting.
- Indexing costs a second model load (a second or two) and up to 2.7 GB of memory
  while it runs, in a process that exits.
- Telemetry is best effort: 3 s timeout, no retry, entries lost while a backend is
  down (the local log keeps them). Tempo needs its OTLP HTTP receiver on.
- The log lines carry `duration_ms` and `embed_ms` from now on; older lines lack them.

## Evidence

- `tests/hooks.rs`: default block with exit code 2 and message for both hooks,
  `keyword` and `allow`, a fresh setup (missing or empty memory and skills
  directories, a server that is down, memories not indexed yet, the index and
  catalogue commands) that is never blocked, a server that comes up 400 ms late,
  a backend that never answers not delaying the hook, a blocked prompt shipped as
  an error span, and the tenant header and absence of the prompt in what is shipped.
- A cache that held vectors for other settings blocks (not a fresh setup); the log
  is locked for appends and rotation, rotates through a temporary file, and lost no
  line with eight concurrent writers through many rotations; credentials come from
  a headers file; the index unit runs at nice 10.
- `claude -p` with throwaway hooks: a hook exiting 2 blocks the prompt even beside a
  hook that succeeds, with no model call; with two blocking hooks one message is
  shown; a successful hook's `additionalContext` reaches the model.
- Real model: after indexing three memories on a separate server and adding a
  fourth, the same query server process (451 MB) returned the new memory at once;
  the temporary server peaked at 1.8 GB and exited.
- Real Loki 3.7.7 and Tempo 2.10.5 run locally received a hook run: the line came
  back with its labels from `query_range`, the trace with the `embed` span parented
  under the hook span, and neither stored the prompt.

## Revisit when

- Blocking proves too disruptive in the trial log's failure count; then the default
  moves to `keyword` with an alert on the failure rate in Loki.
- Claude Code gains a way for a hook to ask the user rather than block.
- Telemetry delivery loss matters; then add a small retry queue or an Alloy hop.
