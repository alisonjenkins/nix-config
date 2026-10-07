# memory-recall: semantic recall of memories and skills

Decision record: [ADR 0029](adr/0029-embedding-retrieval-for-memory-and-skills.md).
Code: `scripts/retrieval-eval/`. Package: `pkgs/memory-recall`. Option:
`modules.memoryRecall` (`home/modules/memory-recall`).

## What it is

Claude Code loads `MEMORY.md` (about 3,900 tokens here) into every session and
every subagent, then relies on the model to pick the right memory file from
one-line summaries. Skills work the same way: a listing of every skill's
description is always in context, and choosing one loads its whole `SKILL.md`,
then whole reference files.

`memory-recall` is a `UserPromptSubmit` hook that embeds the prompt, finds the
closest memories by cosine similarity, and injects only those (path, score and
one-line description). A local EmbeddingGemma 2 server does the embedding.

```
prompt ──▶ memory-recall hook ──▶ llama-server --embeddings (EmbeddingGemma 2, CPU)
              │                         │ prompt vector
              │ cached memory vectors ◀─┘
              ▼
   top 3 above 0.74 ──▶ "Possibly relevant memories: <path> (0.81): <description>"
```

It fails open: no server, a 3 s timeout, no `prompt` in the payload, a prompt
under 12 characters, or nothing above the threshold all inject nothing and exit
0, so it can never block a prompt.

Status: built, tested and benchmarked, **not enabled on any host**. The module
is imported on `ali-desktop` with the option off.

## Components

| Piece | Where |
|---|---|
| Hook and CLI (`memory-recall`), harness (`retrieval-eval`), benchmarks (`recall-bench`, `recall-compare`) | `scripts/retrieval-eval/`, packaged as `pkgs.memory-recall` |
| Embedding model, `embeddinggemma-2-Q8_0.gguf` (296 MiB, hash pinned) | `pkgs.llama-models.embeddinggemma-2-q8-0` |
| llama.cpp new enough for the `gemma-embedding2` architecture | `pkgs.llama-cpp-upstream` (nixpkgs unstable and release v0.6.0 fail with `unknown model architecture`) |
| Server, reindex units and hook wiring | `modules.memoryRecall` |

## Enabling it

```nix
# in the host's home-manager config (the module is already imported on ali-desktop)
modules.memoryRecall = {
  enable = true;
  memoryDir = "${config.home.homeDirectory}/.claude/projects/-home-ali-git-personal-nix-config/memory";
};
```

That adds a `memory-recall-server` user service, a `memory-recall-index`
service plus path unit that re-embeds when a memory file changes (and restarts
the server afterwards, see Operating), and appends the hook to
`programs.claude-code.settings.hooks.UserPromptSubmit`. Options: `threads` (4),
`dims` (256), `top` (3), `minScore` (0.74), `port` (8110), `model`, `llamaCpp`.

The option does **not** trim `MEMORY.md`. Until you shorten it, the hook adds
about 110 tokens per prompt on top of the index. The saving only exists once the
index is replaced by a stub; see "What the benchmarks say".

## Operating it

```bash
BIN=$(nix build --no-link --print-out-paths .#memory-recall)/bin/memory-recall
ARGS=(--memory-dir ~/.claude/projects/<project>/memory
      --embedder 'gemma=gemma@http://127.0.0.1:8110#256'
      --cache ~/.cache/memory-recall/gemma-256.json)

$BIN "${ARGS[@]}" query --top 3 "examplarr cannot log in"   # scores, for calibration
$BIN "${ARGS[@]}" index                                  # embed new or edited memories
systemctl --user status memory-recall-server memory-recall-index.path
journalctl --user -u memory-recall-server -u memory-recall-index
```

- **Cache.** Vectors are cached per memory by a content hash, keyed by the model
  name the server reports. Swapping the model, preset or dimensions discards the
  cache instead of ranking on incompatible vectors. A changed memory re-embeds in
  about 2 s; the first full index takes about 70 s (90 s at 4 threads).
- **Server memory.** The server idles at about 425 MB. Embedding every memory
  makes llama.cpp keep its largest compute buffer (2.1 to 2.7 GB) for good, so
  the index service restarts the server when it finishes. Hooks that land in
  that second inject nothing.
- **Prompt format.** EmbeddingGemma wants `task: search result | query: ...` for
  queries and `title: ... | text: ...` for documents; the `gemma` preset does this.
- **Float16 is unsafe** for this model (NaN); the GGUF is Q8_0.

## Tuning

| Setting | Effect |
|---|---|
| `threads` | llama.cpp's threads spin while waiting, so more threads cost CPU, not just speed. 4 is the knee (below). |
| `dims` | 256 matches 768 on quality at a third of the cache size. 128 is clearly worse on skills. The threshold is **specific to the dimensions**: 128 needs roughly 0.82. |
| `minScore` | 0.74 favours recall. 0.76 trades one missed memory in 28 for half the false injections. |
| `top` | A third injection rarely helps; the average injection is 0.6 memories at 0.74. |

Re-measure the threshold with `recall-bench gate` after changing the model or
dimensions.

## What the benchmarks say

All numbers: AMD Ryzen 9 7950X (16 cores, 32 threads), 62 GiB, kernel
7.2.8-cachyos, llama.cpp `b7dafa0`, EmbeddingGemma 2 Q8_0, run on 2026-10-07.
Raw data is in `scripts/retrieval-eval/bench/results/`. Load average was 11 at
the start of the quality run and rose with the benchmark's own servers, so
timings are if anything pessimistic.

### Retrieval quality (83 memories, 28 queries; 113 skill sections, 20 queries)

Queries are phrased as a symptom or situation, not in the target's own words.

| Retriever | Memories: right file in top 1 / top 3 / top 5 | Skill sections: top 1 / top 3 / top 5 |
|---|---|---|
| BM25 | 64% / 79% / 86% | 55% / 70% / 80% |
| EmbeddingGemma 2, 768 dims | 86% / 96% / 100% | 80% / 100% / 100% |
| 512 dims | 86% / 93% / 100% | not run |
| **256 dims** | **89% / 93% / 96%** | **80% / 100% / 100%** |
| 128 dims | 89% / 96% / 96% | 65% / 80% / 95% |
| BM25 and 256 dims fused (RRF) | 79% / 89% / 89% | not run |

Fusing with BM25 made things worse, so the hook uses embeddings alone.

### The injection threshold (256 dims, 28 relevant, 30 off-topic and 20 adjacent prompts)

"Adjacent" prompts are in the user's own domains (NixOS modules, k3s, sops) but
match no memory; the labels are a judgement call.

| Threshold | Relevant prompts answered | False injection, off-topic / adjacent | Injections that were right | Mean tokens per prompt |
|---|---|---|---|---|
| 0.70 | 93% | 17% / 60% | 58% | 100 |
| 0.72 | 93% | 7% / 35% | 70% | 72 |
| **0.74** | **93%** | **3% / 20%** | **84%** | **48** |
| 0.76 | 89% | 0% / 10% | 93% | 32 |
| 0.78 | 64% | 0% / 5% | 95% | 22 |

Top-1 scores for the right memory ran 0.73 to 0.87; for off-topic prompts 0.53
to 0.76 and for adjacent prompts 0.65 to 0.81, which is why adjacent prompts are
the ones that still slip through.

### Speed and resources

| | Value |
|---|---|
| Hook, end to end (real process, 300 calls, default threads) | p50 17.2 ms, p95 19.4 ms, p99 20.3 ms |
| Hook at 4 threads (the module default) | p50 22.9 ms, p95 27.1 ms |
| Hook process peak memory | 5.7 MB |
| Server idle memory / CPU | 425 to 470 MB / 2 ms per second at 4 threads |
| Server cold start (model warm in page cache) | 0.86 s |
| Full index, 83 memories | 70 s (90 s at 4 threads), 844 ms per memory |
| Re-index, one file edited / nothing changed | 1.8 s / 0.001 s |
| Search at 1,000 / 10,000 / 100,000 memories | 0.17 / 1.8 / 19 ms |
| Cache file at 83 / 1,000 / 10,000 memories | 0.27 / 3.1 / 31 MB (JSON load 0.6 / 5.4 / 57 ms) |

Thread sweep (fresh server per setting, 100 real hook calls each):

| Threads | p50 | p95 | Server CPU per prompt | Idle CPU |
|---|---|---|---|---|
| 1 | 68 ms | 83 ms | 66 ms | 0 ms/s |
| 2 | 39 ms | 46 ms | 75 ms | 0 ms/s |
| **4** | **23 ms** | **27 ms** | **90 ms** | **2 ms/s** |
| 8 | 20 ms | 25 ms | 157 ms | 6 ms/s |
| 16 | 17 ms | 20 ms | 275 ms | 10 ms/s |
| 32 (default) | 17 ms | 19 ms | 272 ms | 10 ms/s |

The cache is plain JSON, so every prompt parses all of it: fine to a few
thousand memories, about 57 ms at 10,000.

### Against the defaults

"Right source" and "facts" are scored against 98 verbatim key facts for the
memory queries (3 to 4 per query, at least one of them only in the memory body,
not its one-line summary) and 80 for the skill queries. A fact counts if the
string appears in the model's answer. The model is `sonnet` at low effort
through an isolated `claude -p` (no tools, no hooks, empty working directory).
Each call carries about 2,900 tokens of fixed overhead, shown in the `none` row.
Single run per query.

**Memory** (28 queries):

| System | Right file chosen | Facts in answer | Answers with every fact | Model input tokens | API time | Local retrieval |
|---|---|---|---|---|---|---|
| no memory | | 9% | 0% | 2,952 | 8.2 s | |
| default, index only | | 39% | 7% | 10,128 | 6.3 s | 0 ms |
| **default, index then read files** | 100% | **90%** | **71%** | 15,338 | 9.4 s | 0 ms |
| memory-recall, snippets only | | 35% | 4% | 3,163 | 6.6 s | 25 ms |
| **memory-recall, then read files** | 93% | 83% | 64% | **7,348** | 8.6 s | 25 ms |
| cavemem, model-formed keywords | | 18% | 0% | 6,248 | 10.9 s | 96 ms |
| cavemem, keywords, full observations | | 24% | 0% | 7,101 | 10.8 s | 96 ms |

**Skills** (20 queries):

| System | Right source chosen | Facts in answer | Answers with every fact | Model input tokens | API time | Local retrieval |
|---|---|---|---|---|---|---|
| no skill | | 16% | 0% | 2,946 | 5.8 s | |
| default, `SKILL.md` only | 20% | 25% | 5% | 15,488 | 8.9 s | 0 ms |
| **default, `SKILL.md` then reference files** | 95% | **74%** | **40%** | 25,191 | 11.2 s | 0 ms |
| BM25 over sections, top 3 | 65% | 49% | 30% | 4,281 | 5.9 s | 0.1 ms |
| **Embedding over sections, top 3** | 95% | **74%** | **40%** | **3,920** | **5.3 s** | 15 ms |

What this means:

- **Skills are the clear win.** Injecting three embedded sections matches the
  default flow's answer quality (74% of facts, 95% right source) for one sixth of
  the tokens (3.9k against 25.2k) and half the model time. The default flow
  that stops at `SKILL.md` finds the right file only 20% of the time, because the
  detail lives in reference files.
- **Memory is a modest win, and only once `MEMORY.md` is trimmed.** The default
  index-then-read flow picked the right file 28 times out of 28 and answered
  best (90%). memory-recall found the right file 26 times out of 28 and used half
  the tokens (7.3k against 15.3k, or 4.4k against 12.4k above the fixed
  overhead). Its two misses, "the github CLI hangs" and "gateway timeouts while it
  swaps", are the same two BM25 missed. At 83 memories the index is cheap and the
  model reads it well; the case grows with the number of memories, because the
  index grows with them and an injection does not.
- **A snippet is not the memory.** The injected one-line description carries 93%
  of the description facts and none of the body-only facts, as does the index
  line. Answering from a snippet alone scores 35% against 83% after opening the
  file. The hook points at the file; the model still has to read it.
- **cavemem is the wrong tool for this job, not a bad one.** It searches past
  session transcripts, not curated memories. Here its semantic half is off
  (`@xenova/transformers` is missing from the Nix package and its embedding
  backfill is at 0 of 164,212), leaving full-text search that requires every word
  to match: a raw prompt returns nothing, and model-formed keywords return
  tool-output noise. It kept 18 to 24% of the facts.
- **Cost in dollars understates the token gap**, because the repeated index and
  skill listing are served from the prompt cache. Input tokens are the cleaner
  comparison; dollars per query were $0.041 against $0.031 for memory and $0.080
  against $0.020 for skills.

### Caveats

- 28 and 20 queries, written by the same author as the key facts, so the
  queries probably favour the embedding model's strength at paraphrase. They are
  paraphrases by construction.
- Fact scoring is a substring match, so a correct answer in different words
  scores low and a keyword dump scores high. It measures whether the detail
  reached the answer, not whether the answer is good.
- One model, one effort level, one run. Differences of a few points between
  rows (74% against 74%, 83% against 90%) are within what another run could move.
- Memory retrieval was timed as a real hook process (25 ms) but skills
  retrieval in-process (15 ms); a skills hook would add process start and a
  cache load, which I have not measured.
- cavemem was queried against a read-only copy of its database cut off before the
  benchmark day, so this session could not answer its own test. A marker string
  in every prompt confirms the isolated calls were not captured.
- Token counts for retrieval use bytes divided by four; model tokens come from
  the API's usage field.

## Limitations and open work

- **No skills hook yet.** The skills result above is measured, not deployed; the
  hook only handles memories. Building it needs the sections of every skill
  embedded (656 sections, which took several minutes the first time; not timed)
  and a per-section size cap (the benchmark used 3,000 characters).
- **One project's memories.** Claude keeps one memory directory per project, and
  `memoryDir` names one.
- **Subagents.** Whether `UserPromptSubmit` fires for them, and so whether they
  would get the injection, is unchecked.
- **Linux only**, because the units are systemd.
- **The threshold is calibrated on this model, size and corpus.**

## Reproducing

```bash
nix develop path:scripts/retrieval-eval --command cargo test
# 25 minutes, quality / threshold / latency / threads / indexing / scaling:
nix develop path:scripts/retrieval-eval --command env MEMORY_DIR=... \
  scripts/retrieval-eval/bench/run.sh
# memory and skills against the defaults; set NO_LLM=1 to skip the model calls:
nix develop path:scripts/retrieval-eval --command env MEMORY_DIR=... \
  scripts/retrieval-eval/bench/compare.sh
# re-print the saved comparison tables without any model calls:
scripts/retrieval-eval/target/release/recall-compare render \
  scripts/retrieval-eval/bench/results/compare-skills.json
```

The query sets (`queries/memory.json`, `skills.json`, `negatives.json`,
`facts.json`, `skills-facts.json`) are a 2026-10-07 snapshot; run
`retrieval-eval --validate-only` after memories or skills change.
