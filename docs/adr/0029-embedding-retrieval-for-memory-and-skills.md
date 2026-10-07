# 0029. Retrieve memories and skill sections by embedding, behind an option

- Status: Proposed. Built and benchmarked. What the hook injects, the thresholds
  and the conclusion that memories pay off only once `MEMORY.md` is trimmed are
  superseded by
  [0030](0030-inject-confident-memories-and-use-a-catalogue.md).
- Date: 2026-10-07

## Context

Claude Code pays for knowledge in two ways that grow with how much we know.

- **Memories.** `MEMORY.md` is loaded into every session and every subagent:
  3,905 tokens for 83 memories. The model reads one-line summaries and opens the
  file it thinks applies.
- **Skills.** A listing of every skill's description is always in context
  (4,247 tokens for the 39 skills in `~/.claude/skills`, as the benchmark builds
  it; Claude Code itself caps the listing at 1% of the context window), and
  choosing a skill loads its whole `SKILL.md`, then
  whole reference files. For the 20 questions we tried, that loaded 25,191 model
  input tokens against a 2,946-token baseline.

The idea (notes on EmbeddingGemma 2): embed the prompt, find the nearest
memories or skill sections, and inject only those. Nobody had measured whether
that beats the defaults here, or what it costs, so before wiring anything in
this record asks: is it better, and is it worth running a model for it?

## Decision

Build it, keep it off by default, and measure it against the defaults.

- `modules.memoryRecall` (`home/modules/memory-recall`) runs a local
  `llama-server --embeddings` with EmbeddingGemma 2 Q8_0 on CPU, a
  `UserPromptSubmit` hook (`memory-recall hook`) and a reindex path unit. It
  fails closed: when it cannot retrieve memories it blocks the prompt (exit 2).
- Settings, each from a measurement in `docs/memory-recall.md`: 256-dimension
  vectors, injection threshold 0.74, top 3, server threads 4, and each reindex on
  its own short-lived server so the query server never restarts.
- The model is `pkgs.llama-models.embeddinggemma-2-q8-0` and the server is
  `pkgs.llama-cpp-upstream`, pinned to upstream commit `b7dafa0`, because
  nixpkgs' llama.cpp does not know the `gemma-embedding2` architecture.
- The code is a Rust crate, `scripts/retrieval-eval`, packaged as
  `pkgs.memory-recall`. It holds the hook, the eval harness and the benchmarks.

What the evidence supports next, and what this record does **not** do:

- Skills are the strong case. Build a skills hook before anything else.
- Memories are a modest case, and only if `MEMORY.md` is trimmed to a stub. This
  record does not trim it and does not enable the option.

## Alternatives rejected

- **BM25.** 64% / 79% / 86% for the right memory in the top 1 / 3 / 5, against
  89% / 93% / 96% for embeddings, and 65% right-source on skills against 95%.
- **Fusing BM25 with the embeddings** (reciprocal rank fusion): worse than
  embeddings alone, 79% / 89% / 89%.
- **128-dimension vectors.** Fine for memories (89% / 96% / 96%) but 65% / 80% /
  95% on skill sections, and the injection threshold moves to about 0.82.
  **768 dimensions** buys nothing over 256 and triples the cache.
- **Letting llama.cpp use every thread.** 17 ms against 23 ms per prompt, but
  272 ms of CPU against 90 ms, and 10 ms/s of idle CPU against 2, because its
  threads spin while waiting.
- **cavemem as the memory retriever.** It searches past session transcripts, not
  curated memories. In this install its semantic half is off (`semantic
  disabled: Local embedding provider requires @xenova/transformers`, embedding
  backfill 0 of 164,212), so it is full-text search that needs every word to
  match: a raw prompt returned nothing, and with model-formed keywords it kept
  18 to 24% of the facts against 83 to 90% for the file-reading flows.
- **Python harness; Kaggle as the model source.** Rust was asked for. Kaggle
  needs credentials (anonymous access returns 404), so the GGUF comes from
  Hugging Face, hash pinned.
- **ONNX or candle inside the hook.** No Rust runtime supports the
  EmbeddingGemma 2 architecture, and loading a model per prompt costs 0.86 s.
  An HTTP call to a resident `llama-server` costs about 20 ms.
- **Indexing on the long-lived query server.** Embedding makes llama.cpp keep its
  largest compute buffer: 425 MB grows to 1.6 GB after one long memory and 2.7 GB
  after a full index, and stays. `-np 1`, `MALLOC_ARENA_MAX=1` and `--threads-http
  2` did not stop it; `-ub 512` fails on long memories. Restarting the query
  server after each index (the first design) worked but interrupted prompts; each
  index now runs on its own short-lived server instead.

## Consequences

- **Cost when enabled:** about 425 MB of resident memory, about 90 ms of CPU per
  prompt, 23 ms added to each prompt, a 5.7 MB hook process, and a JSON vector
  cache that parses in 57 ms at 10,000 memories.
- **Until `MEMORY.md` is trimmed it costs tokens:** the hook adds about 110 per
  prompt on top of the index. The saving, 4.4k against 12.4k tokens per question
  above the fixed overhead, needs the index gone.
- **It will sometimes inject the wrong memory.** At 0.74, 3% of off-topic and 20%
  of adjacent prompts get an injection, and 84% of injections are right. It will
  sometimes miss: 2 of 28 queries, the same two BM25 missed.
- **A snippet is not the memory.** The injected description holds none of the
  detail that is only in the body; the model still opens the file.
- The threshold is only valid for this model, dimension count and corpus. Changing
  any of them means re-running `recall-bench gate`.
- **A prompt must not lose its memories and skill sections**, as it could ignore
  the guard rails they hold (a bad mistake such as deleting a production server is
  worse than a refused prompt). The hooks retry for 1.5 s (a server that is
  starting or has just crashed) and then, by default, block the prompt (exit 2,
  with a message). `--on-unavailable keyword` injects BM25 matches instead and `allow`
  lets the prompt through bare; both are opt-in. The cost of the default is that
  Claude Code stops answering while the embedding server is down.
- The Nix package builds the whole crate, including the benchmarks, so a
  `Cargo.lock` bump must keep `nix build .#memory-recall` green.

## Evidence

- Quality, threshold sweep, latency, thread sweep, indexing, scaling:
  `scripts/retrieval-eval/bench/run.sh`, raw output in `bench/results/`.
- Memory and skills against the defaults and cavemem:
  `bench/compare.sh`, `bench/results/compare-memory.json` and
  `compare-skills.json`. Re-print with `recall-compare render`.
- Ground truth: 98 key facts about real memories (private; git holds placeholders,
  see `queries/README.md`) and `skills-facts.json` (80),
  every fact checked to be a verbatim substring of its source by an independent
  script; the skills comparison refuses to run if one is not.
- The first thread sweep was invalid (the driver lost the server's PID and
  measured one server five times); it was found from empty `server RSS` fields,
  fixed in `bench/lib.sh` and rerun. Both drivers now refuse to start if the port
  already answers.
- `systemd-analyze verify` on the generated units; transient units confirmed that
  `PathChanged` on a directory fires for an edit to an existing file inside it and
  that a oneshot's `ExecStartPost=systemctl --user try-restart` restarts a sibling
  (that design has since been replaced; see above).
- Index on a separate server (2026-10-08, real model): the query server kept its
  pid and 451 MB through two index runs, the temporary server peaked at 1.8 GB and
  exited, and a memory added between the runs was found by the next hook.
- **macOS.** The module also runs on macOS, as launchd agents (the work Mac is a
  target). Evaluated for `aarch64-darwin` in a scratch flake pinned to the commit
  (agents, hooks, activation package); not built or run on a Mac. See
  `docs/memory-recall.md`.
- The model calls ran through `claude -p` with no tools, settings limited to an
  empty directory (so no hooks) and a marker string in every prompt. A search of
  cavemem's database for the marker found one hit, this session's own `Write` of
  the check script.

## Revisit when

- nixpkgs' llama.cpp knows `gemma-embedding2`: drop `pkgs.llama-cpp-upstream`.
- The memory count passes a few hundred, so the index costs 15k tokens or more:
  the memory case gets much stronger.
- A skills hook is measured end to end and does not hold the 74% / 95% result.
- cavemem's embeddings are working (install `@xenova/transformers`, let the
  backfill finish): re-run `bench/compare.sh` before judging it again.
- A different model or dimension count is used: re-calibrate the threshold.
