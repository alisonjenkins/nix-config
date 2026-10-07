# memory-recall: semantic recall of memories and skills

Decision records: [ADR 0029](adr/0029-embedding-retrieval-for-memory-and-skills.md)
(why embeddings, how it runs) and
[ADR 0030](adr/0030-inject-confident-memories-and-use-a-catalogue.md) (what it
injects, and the names-only index). Code: `scripts/retrieval-eval/`. Package:
`pkgs/memory-recall`. Option: `modules.memoryRecall` (`home/modules/memory-recall`).

## What it is

Claude Code loads `MEMORY.md` (3,905 tokens here) into every session and every
subagent, then relies on the model to pick a memory file from one-line summaries
and open it. Skills work the same way: a listing of every skill's description is
always in context, choosing one loads its whole `SKILL.md`, then whole reference
files.

`memory-recall` is a `UserPromptSubmit` hook that embeds the prompt with a local
EmbeddingGemma 2 server, finds the closest memories by cosine similarity, and puts
them in front of the model:

```
prompt ──▶ memory-recall hook ──▶ llama-server --embeddings (EmbeddingGemma 2, CPU)
              │                         │ prompt vector
              │ cached memory vectors ◀─┘
              ▼
   score ≥ 0.76 ─▶ the whole memory, injected          (about 1,000 tokens; the model answers at once)
   0.70 – 0.76  ─▶ "<path> (0.73): <description>"      (about 35 tokens; the model opens the file if it fits)
   below 0.70   ─▶ nothing
```

At most 3 matches. It fails open: no server, a 3 s timeout, no `prompt` in the
payload, a prompt under 12 characters, or nothing above the floor all inject
nothing and exit 0, so it can never block a prompt.

**What the evidence supports** (details below): the injection gets facts into the
answer as often as the strongest default flow (one that always reads a file), and
10 points more often than a model that opens files only when it asks to, with
30 to 38% less model time. It
does so at roughly half the tokens **if** `MEMORY.md` is replaced by a names-only
catalogue (`memory-recall catalogue`); with the full index kept it is faster and
more accurate than the default, and in dollars level with a model that opens files
only when it asks (see the dollar-cost caveat below).

Status: built, tested and benchmarked, **not enabled on any host**. The module is
imported on `ali-desktop` with the option off.

## Components

| Piece | Where |
|---|---|
| Hooks and CLIs (`memory-recall`, `skill-recall`), harness (`retrieval-eval`), benchmarks (`recall-bench`, `recall-compare`, `recall-experiment`) | `scripts/retrieval-eval/`, packaged as `pkgs.memory-recall` |
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

That adds a `memory-recall-server` user service, a `memory-recall-index` service
plus path unit that re-embeds when a memory file changes (and restarts the server
afterwards, see Operating), and appends the hook to
`programs.claude-code.settings.hooks.UserPromptSubmit`. Options: `inject`
(`auto`), `minScore` (0.70), `bodyScore` (0.76), `top` (3), `threads` (4), `dims`
(256), `port` (8110), `model`, `llamaCpp`.

`skills.enable = true` adds `skill-recall`, a second hook that injects up to
`skills.top` (3) skill sections scoring at least `skills.minScore` (0.74), and
indexes `skills.root` (`~/.claude/skills`) beside the memories. The path unit
watches the skills root without recursion: a new skill folder is indexed at once,
an edit inside one at the next login or `systemctl --user start memory-recall-index`.

**The trial.** Both hooks append one line per prompt to `logFile`
(`~/.local/state/memory-recall/recall.jsonl`): time, best score, matches, how many
in full, tokens added; never the prompt. After a few weeks of use:

```bash
memory-recall log-summary ~/.local/state/memory-recall/recall.jsonl
```

prints, per hook, the share of prompts that got an injection, the share that got a
whole memory (for skills, every injected section counts), the average tokens added
per prompt and per injection, the median best score, and how many prompts the hook
gave up on (server down, timeout, missing cache), which are not counted in the
other columns. The log is capped: at 1 MiB (about 10,000 prompts) it moves to
`recall.jsonl.1.gz`, older files shift up, and past `.5.gz` they are deleted;
`log-summary` reads the rotated files too. Adopt the catalogue when the average tokens added per prompt stay under
the roughly 3,100 tokens per session the catalogue saves (spec 006, SC-006); record
the decision and the numbers in an ADR. `ali-desktop` has it enabled (not yet
switched to).

**To get the token saving**, also replace the index with the catalogue:

```bash
memory-recall --memory-dir <memoryDir> catalogue --write <memoryDir>/MEMORY.md
```

That turns 15,621 bytes (3,905 tokens) into 3,135 bytes (about 780 tokens): one
line per memory file, no descriptions. It is **your file**, and Claude's own
memory-saving appends a line to `MEMORY.md` when it writes a new memory, so rerun
the command after new memories appear (it only writes when the content changed).
Nothing here does that for you, on purpose.

## Operating it

```bash
BIN=$(nix build --no-link --print-out-paths .#memory-recall)/bin/memory-recall
ARGS=(--memory-dir ~/.claude/projects/<project>/memory
      --embedder 'gemma=gemma@http://127.0.0.1:8110#256'
      --cache ~/.cache/memory-recall/gemma-256.json)

$BIN "${ARGS[@]}" query --top 3 "examplarr cannot log in"   # scores, for calibration
$BIN "${ARGS[@]}" index                                  # embed new or edited memories
$BIN --memory-dir ~/.claude/projects/<project>/memory catalogue   # the names-only index
systemctl --user status memory-recall-server memory-recall-index.path
journalctl --user -u memory-recall-server -u memory-recall-index
```

- **Cache.** Vectors are cached per memory by a content hash, keyed by the model
  name the server reports and how documents are wrapped. Swapping the model,
  prompt format or dimensions discards the cache instead of ranking on
  incompatible vectors. A changed memory re-embeds in about 2 s; the first full
  index takes about 70 s (90 s at 4 threads).
- **Server memory.** The server idles at about 425 MB. Embedding every memory
  makes llama.cpp keep its largest compute buffer (2.1 to 2.7 GB) for good, so
  the index service restarts the server when it finishes. Hooks that land in that
  second inject nothing.
- **A server that suddenly takes seconds per query.** Seen once, during the
  benchmarks: a freshly restarted server (nothing bulk-embedded, `--threads 4`,
  `nice -n 10`, not pinned) answered a 40-token query in about 3 s with 27 cores
  busy, while the machine's load average was 54. The same binary pinned to 8 CPUs
  at `nice -n 19` answered in 13 ms. The cause is unconfirmed; spinning worker
  threads being descheduled under CPU contention is the suspect. Check the load
  average first, and pin a benchmark server with `CPUSET=24-31` (see `bench/lib.sh`).
- **Prompt format.** EmbeddingGemma wants `task: search result | query: ...` for
  queries and `title: ... | text: ...` for documents; the `gemma` preset does this.
- **Float16 is unsafe** for this model (NaN); the GGUF is Q8_0.
- **Run benchmark servers at low priority.** An unthrottled embedding server can
  starve a real-time audio session; the bench drivers use `nice -n 10`.

## Tuning

| Setting | Effect |
|---|---|
| `inject` | `auto` (default): full text from `bodyScore`, snippets from `minScore`. `snippets`: never a body, the model opens the file. `top` / `all`: the best, or every, match in full. |
| `minScore` | Floor for any injection. 0.70 leans to recall: the right memory's best score ran 0.70 to 0.87 over 58 queries, and a stray snippet costs about 35 tokens. |
| `bodyScore` | From here a match is injected whole. Higher than the floor because a wrong whole memory is the expensive mistake. |
| `threads` | llama.cpp's threads spin while waiting, so more threads cost CPU, not just speed. 4 is the knee (below). |
| `dims` | 256 matches 768 on quality at a third of the cache size. 128 is clearly worse on skills. **The thresholds are specific to the dimensions**: 128 needs roughly 0.82. |

Re-measure the thresholds with `recall-bench gate` and `recall-experiment` after
changing the model or dimensions.

## What the benchmarks say

All numbers: AMD Ryzen 9 7950X (16 cores, 32 threads), 62 GiB, kernel
7.2.8-cachyos, llama.cpp `b7dafa0`, EmbeddingGemma 2 Q8_0, run on 2026-10-07.
Raw data is in `scripts/retrieval-eval/bench/results/`. Load average was 11 at the
start of the quality run and rose with the benchmark's own servers, so timings are
if anything pessimistic.

Two query sets, so tuning is judged on queries it was not tuned on: **dev** (28
queries, used to choose settings) and **held-out** (30 queries over 30 other
memories, written by a separate agent without seeing any retrieval result). Both
are phrased as a symptom or situation, not in the target's own words.

### Closing the gap with Claude's default memory

The first end-to-end run had memory-recall behind the default on facts in the
answer (83% against 90%, dev). Per query the cause was plain: on the 26 queries
where it found the right file its answers matched the default's, and on the 2 it
missed it scored 0 of 4 facts each. The held-out set told the same story (3 more
misses), and the default again picked the right file every time.

*Why it misses.* Of the 5 misses over both sets, 2 ranked the right memory **first**
and were thrown away by the 0.74 gate (scores 0.70 and 0.71); 3 were ranked 5th
to 7th behind near-identical notes (for example an audio note beaten by two other
audio notes). For the first two the gate was the bottleneck, for the rest the
ranking. Nothing separates right from wrong cleanly: the right memory's top score
has a tail down to 0.70, and in-domain prompts with no memory ("add a NixOS
module") reach 0.76 to 0.81.

*Re-embedding does not fix it.* Eight ways of embedding a memory (full text,
description alone, 600-character body chunks scored per file; each with the
search-result, question-answering and sentence-similarity query prompts), and
z-score fusions of them with and without BM25 (`bench/results/retrieval-variants.md`):

| Strategy | Dev: right memory in top 1 / 3 / 5 | Held-out: top 1 / 3 / 5 |
|---|---|---|
| **full text (shipped)** | 89 / 93 / 96 | 90 / 97 / 97 |
| full text, question-answering prompt | 89 / 93 / 100 | 90 / 97 / 100 |
| description alone | 86 / 93 / 96 | 83 / 90 / 93 |
| body chunks, best chunk per file | 86 / 96 / 96 | 90 / 97 / 100 |
| full + description + chunks, fused | 93 / 96 / 100 | 87 / 97 / 97 |
| the same, plus BM25 | 89 / 93 / 100 | 93 / 97 / 100 |
| sentence-similarity prompt | 79 / 93 / 93 | 63 / 80 / 83 |
| BM25 alone | 64 / 79 / 86 | 80 / 93 / 93 |

Differences are one or two queries and do not hold across the two sets (the
fusions win one and lose the other), so the representation stays as it was.

*What did help.* Three changes, all after retrieval:

1. **Tiered injection** (`--inject auto`): a match from 0.70 goes in as a one-line
   snippet instead of being dropped, and one from 0.76 goes in whole so the model
   answers without opening a file.
2. **Model behaviour closer to Claude's.** The first comparison forced "choose
   files, then read them". A model with a Read tool opens files only when it
   decides to, so the comparison now lets it answer from its context or reply
   `OPEN: <file>`. The default then looks worse (79% against 90%): left to decide,
   the model often answers from the one-line index and never opens the file.
3. **A names-only catalogue instead of the full index.** The model only needs a
   name to open a file when nothing was injected, and the names are descriptive.

All 58 queries (215 key facts), pooled; each query's own model reads only its
context and the files it opens:

| System | Facts in answer | Answers with every fact | Model input tokens | Model time |
|---|---|---|---|---|
| default, open files only if needed (`default_open`) | 79% | 51% | 19,280 | 9.1 s |
| default, forced choose-then-read (`default_read`) | 90% | 72% | 15,293 | 8.0 s |
| full index + tiered injection (`hybrid_open`) | 89% | 68% | 13,047 | 5.8 s |
| tiered injection alone, no index (`recall_auto_open`) | 80% | 60% | 4,860 | 6.4 s |
| **names-only catalogue + tiered injection (`slim_open`)** | **89%** | **67%** | **6,857** | **5.7 s** |

By set (facts in answer / model input tokens / model time):

| System | Dev | Held-out |
|---|---|---|
| `default_open` | 85% / 19.5k / 9.4 s | 74% / 19.0k / 8.8 s |
| `default_read` | 93% / 15.2k / 8.9 s | 88% / 15.4k / 7.3 s |
| `hybrid_open` | 93% / 12.7k / 6.0 s | 86% / 13.4k / 5.6 s |
| `recall_auto_open` | 82% / 4.8k / 6.5 s | 80% / 4.9k / 6.2 s |
| `slim_open` | 91% / 6.5k / 5.5 s | 88% / 7.2k / 5.8 s |

Against the **default modelled as a reader that opens files only when it asks to**
(`default_open`), the catalogue plus injection gives +10 points of facts in the answer, +16 points of answers with
every fact, 64% fewer model input tokens, 38% less model time and 43% less cost.
Against the **strongest default** (`default_read`, which always reads), it is level
(89% against 90%, one point, inside the noise) at 55% fewer tokens and 30% less
time. The injection alone, with no index, falls 10 points short: the index (or
catalogue) is what lets the model recover when retrieval misses.

### Retrieval quality (83 memories, 28 queries; 113 skill sections, 20 queries)

| Retriever | Memories: right file in top 1 / 3 / 5 | Skill sections: top 1 / 3 / 5 |
|---|---|---|
| BM25 | 64% / 79% / 86% | 55% / 70% / 80% |
| EmbeddingGemma 2, 768 dims | 86% / 96% / 100% | 80% / 100% / 100% |
| 512 dims | 86% / 93% / 100% | not run |
| **256 dims** | **89% / 93% / 96%** | **80% / 100% / 100%** |
| 128 dims | 89% / 96% / 96% | 65% / 80% / 95% |
| BM25 and 256 dims fused (RRF) | 79% / 89% / 89% | not run |

### The injection threshold (256 dims, full-text vectors)

Share of right memories injected, and of in-domain memory-less ("adjacent") prompts
that get an injection anyway, at a fixed floor:

| Floor | Dev: right memory injected, false injection off-topic / adjacent | Held-out: same |
|---|---|---|
| 0.70 | 93%, 13% / 50% | 93%, 20% / 70% |
| 0.72 | 93%, 7% / 40% | 90%, 7% / 30% |
| 0.74 | 93%, 7% / 20% | 90%, 0% / 20% |
| 0.76 | 89%, 0% / 10% | 83%, 0% / 10% |
| 0.78 | 64%, 0% / 0% | 60%, 0% / 10% |

The tiered default takes the 0.70 floor for snippets and 0.76 for whole memories,
so the 50 to 70% of adjacent prompts that get a snippet cost about 35 tokens each,
and only about 10% of them get a whole memory.

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

The cache is plain JSON, so every prompt parses all of it: fine to a few thousand
memories, about 57 ms at 10,000.

### Skills, and cavemem

These are the first-round results (single forced flow, 28 and 20 queries), kept
because the skills case has not been rerun with the tiered injection.

**Skills** (20 queries):

| System | Right source chosen | Facts in answer | Answers with every fact | Model input tokens | Model time |
|---|---|---|---|---|---|
| no skill | | 16% | 0% | 2,946 | 5.8 s |
| default, `SKILL.md` only | 20% | 25% | 5% | 15,488 | 8.9 s |
| **default, `SKILL.md` then reference files** | 95% | **74%** | **40%** | 25,191 | 11.2 s |
| BM25 over sections, top 3 | 65% | 49% | 30% | 4,281 | 5.9 s |
| **Embedding over sections, top 3** | 95% | **74%** | **40%** | **3,920** | **5.3 s** |

Injecting three embedded skill sections matches the default flow's answer quality
for one sixth of the tokens and half the model time. The default that stops at
`SKILL.md` finds the right file only 20% of the time, because the detail lives in
reference files.

**cavemem** (memory, 28 queries) is the wrong tool for this job, not a bad one: it
searches past session transcripts, not curated memories. Here its semantic half is
off (`@xenova/transformers` is missing from the Nix package and its embedding
backfill is at 0 of 164,212), leaving full-text search that requires every word to
match: a raw prompt returns nothing, and model-formed keywords return tool-output
noise. It kept 18 to 24% of the facts.

### Caveats

- 28 + 30 queries for memory and 20 for skills. The dev queries were written by the
  same author as their key facts; the held-out ones by a separate agent. Both are
  paraphrases by construction, which suits an embedding model.
- Fact scoring is a substring match, so a correct answer in different words scores
  low and a keyword dump scores high. It measures whether the detail reached the
  answer, not whether the answer is good.
- One model (`sonnet`, low effort), one run per query. Differences of 2 to 3 points
  are within what another run could move: the same `default_read` scored 85% and
  88% on the held-out set in two runs.
- **The emulation decides the default's score.** `default_open` assumes a model
  that opens a file only when it says `OPEN:`; a model that reads more diligently
  would land between it and `default_read`. The comparison that does not depend on
  that is the one against `default_read`, which always reads: level on facts, half
  the tokens.
- Every comparison query has a matching memory. Real prompts mostly do not, and
  those cost the injection's overhead (about 35 tokens per stray snippet, about
  1,000 per stray whole memory at the 10% of adjacent prompts that reach 0.76)
  with nothing gained. At a guessed 15% of prompts having a memory the average is
  about 200 tokens per prompt, and an injected memory stays in the conversation
  for later turns.
- Dollar cost: an earlier run showed the injection systems costing more than
  `default_read`. That was a harness artifact: per-query text sat in the system
  block, so every call missed the cache. With stable text in the system block,
  per-query text in the user turn (as Claude Code does) and the open flow's second
  call resuming the first call's conversation, `hybrid_open` and `slim_open` cost
  $0.025 to $0.028 per query on both sets, against $0.041 to $0.042 for
  `default_read` and `default_open` (about 33 to 40% less). Raw:
  `bench/results/cost-memory-*.md`, which now show cache reads and writes.
  Most of a call's price is the fixed Claude Code prompt and the output, so the
  catalogue's 64% token saving over `default_open` is a smaller dollar saving, and
  cache writes (billed at twice the input rate) are a large part of every system's
  bill. Costs are single runs and moved by up to $0.014 for the same system between
  two runs (`default_open`: $0.027 then $0.041), so read the gap to the defaults,
  not differences between the injection systems. Skills: `sections_embed` $0.020
  per query against $0.086 for `default_load` (`cost-skills.md`); its
  multi-call flows still resend their text rather than resume.
- Memory retrieval was timed as a real hook process (25 ms) but skills retrieval
  in-process (15 ms).
- cavemem was queried against a cut-off copy of its database so this session could
  not answer its own test; a marker in every prompt confirms the isolated model
  calls were not captured.
- Token counts for retrieval use bytes divided by four; model tokens come from the
  API's usage field.

## Limitations and open work

- **The skills hook is built but only trialled, and it saves less than the
  benchmark suggests.** `skill-recall` injects up to 3 sections at or above 0.74.
  The benchmark's $0.020 against $0.086 per query came from an unconditional top 3
  replacing whole-file loads; the hook needs a floor, and at the floor that keeps
  false injections to 20% of off-topic prompts the right section is in the top 3
  for 70% of queries (95% with no floor), at about 240 tokens a prompt. It does not
  shrink the skill listing Claude Code puts in every session, so it saves tokens
  only when it spares the model loading a whole skill file. Whether it does is what
  the trial measures.
- **One project's memories, injected everywhere.** Claude keeps one memory
  directory per project, and `memoryDir` names one. The hook runs in every
  project, so the nix-config memories are offered to prompts in unrelated
  projects; the trial log shows how often that costs tokens for nothing.
- **Subagents.** Whether `UserPromptSubmit` fires for them, and so whether they
  would get the injection, is unchecked.
- **`MEMORY.md` is Claude's file.** The catalogue replaces it by hand; nothing
  regenerates it, and a new memory Claude saves adds a line to it until you rerun
  the command.
- **Linux only**, because the units are systemd.
- **The thresholds are calibrated on this model, size and corpus** (83 memories).

## Reproducing

```bash
nix develop path:scripts/retrieval-eval --command cargo test
# 25 minutes, quality / threshold / latency / threads / indexing / scaling:
nix develop path:scripts/retrieval-eval --command env MEMORY_DIR=... \
  scripts/retrieval-eval/bench/run.sh
# memory (dev and held-out) and skills against the defaults; NO_LLM=1 skips the model calls:
nix develop path:scripts/retrieval-eval --command env MEMORY_DIR=... \
  scripts/retrieval-eval/bench/compare.sh
# the retrieval-variants experiment (~12 minutes):
nix develop path:scripts/retrieval-eval --command env MEMORY_DIR=... \
  scripts/retrieval-eval/bench/variants.sh
# re-print a saved comparison without any model calls:
scripts/retrieval-eval/target/release/recall-compare render \
  scripts/retrieval-eval/bench/results/compare-memory-heldout-slim.json
```

The memory query sets (`memory.json`, `facts.json`, `heldout-facts.json`) name
private notes, so git holds four-query placeholders; keep your own in
`queries/private/` and set `MEMORY_QUERIES_DIR` (`queries/README.md`). The saved
results were measured on the real sets and show `Example question N` and
`example-memory-N.md` in place of the real text, with every number unchanged. The
skills and negatives sets (`skills.json`, `skills-facts.json`, `negatives.json`) are
real. All are a 2026-10-07 snapshot; run
`retrieval-eval --validate-only` after memories or skills change. The
`compare-memory-*-open`, `-slim` and `-injection` result files are subsets of the
memory comparison run separately as systems were added; `compare.sh` now produces
them in one pass.
