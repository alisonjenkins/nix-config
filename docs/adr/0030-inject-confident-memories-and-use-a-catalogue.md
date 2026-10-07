# 0030. Inject confident memories in full, and keep a names-only catalogue

- Status: Proposed. Built and measured, not enabled on any host.
- Date: 2026-10-07
- Supersedes the injection settings and the memory conclusion of
  [0029](0029-embedding-retrieval-for-memory-and-skills.md). The rest of 0029 stands.

## Context

ADR 0029 built a hook that injects the memories closest to each prompt. Its first
end-to-end comparison had it behind Claude's default memory on facts in the
answer: 83% against 90% on 28 dev queries, with the injected one-line snippet and
the model choosing a file to read.

Why, per query: on the 26 queries where it found the right file its answers
matched the default's; on the 2 it missed it scored 0 of 4 facts each. A second
set of 30 held-out queries (written by a separate agent, over memories the dev
set never touches, without seeing any retrieval result) showed the same: the
default picked the right file every time, memory-recall missed 3.

Diagnosis (`bench/results/retrieval-variants.md`, `docs/memory-recall.md`):

- Of the 5 misses over both sets, 2 ranked the right memory first and were
  dropped by the 0.74 gate, at scores 0.70 and 0.71. The other 3 were ranked 5th
  to 7th behind near-identical notes.
- The right memory's top score has a tail down to 0.70; in-domain prompts with no
  memory reach 0.76 to 0.81. No threshold separates them.
- Eight ways of embedding a memory and several fusions moved recall by one or two
  queries in different directions on the two sets.

The first comparison also forced the default into "name files, then read them".
Claude with a Read tool opens a file only when it decides to. Letting the model
answer from its context or reply `OPEN: <file>` made the default look worse, which
changes what "beating the default" means: 79% pooled over 58 queries, against 90%
for the forced version.

## Decision

- **Inject in tiers** (`memory-recall hook --inject auto`, now the default). A
  match scoring at least 0.70 goes in as a one-line snippet; at least 0.76, as the
  whole memory (cut at 3,500 characters), so the model answers without opening a
  file. At most 3 matches. `modules.memoryRecall` gains `inject` and `bodyScore`;
  `minScore` is now 0.70.
- **Replace the index with a names-only catalogue** (`memory-recall catalogue
  --write <memoryDir>/MEMORY.md`): 3,135 bytes against 15,621. The model opens a
  file by name when nothing was injected. This is a step the user takes, not one
  the module takes: `MEMORY.md` is Claude's file.
- **Keep the representation:** full-text vectors, 256 dimensions, the
  search-result prompt.
- **Judge settings on the held-out set**, which `bench/compare.sh` now runs beside
  the dev set.

## Alternatives rejected

Pooled over 58 queries, facts in the answer / model input tokens / model time:

| Option | Result | Why not |
|---|---|---|
| Keep `MEMORY.md` as is, no injection (`default_open`, modelled as a reader that opens files only when it asks to) | 79% / 19.3k / 9.1 s | The status quo this beats, on that model of it. |
| Forced choose-then-read (`default_read`) | 90% / 15.3k / 8.0 s | Always reads a file, which Claude need not do; the ceiling to compare with. |
| Full index plus tiered injection (`hybrid_open`) | 89% / 13.0k / 5.8 s | As accurate, but 2x the tokens of the catalogue. A fine choice if `MEMORY.md` must stay untouched. |
| Tiered injection alone, no index (`recall_auto_open`) | 80% / 4.9k / 6.4 s | 9 points worse; nothing to fall back on when retrieval misses. |
| Always inject whole memories (`top`, `all`) | 76 to 81% / 4.2 to 4.8k (held-out only) | Same fallback problem, and wrong whole memories on every false match. |
| Snippets only (the 0029 setting) | 26 to 35% | The model has to open the file, and the one-line description holds none of the detail that is only in the body. |
| **Catalogue plus tiered injection (`slim_open`)** | **89% / 6.9k / 5.7 s** | Chosen. |

Retrieval changes, none adopted: description-only vectors; body chunks scored per
file; the question-answering and sentence-similarity query prompts; z-score
fusions of these; fusion with BM25 (held-out top-3 recall 90 to 97% for the
alternatives against 97% for the shipped full-text vectors, and the best
alternative differed between the dev and held-out sets).

A model-based reranker or gate would separate the confusable cases but costs a
model call on every prompt, which is the cost this removes.

## Consequences

- **The always-loaded index drops from about 3,900 to about 780 tokens**, in every
  session and every subagent, once the catalogue is adopted. Descriptions are no
  longer in context; the model sees names and what the hook injects.
- **Prompts with no matching memory pay for the injection.** About 35 tokens per
  stray snippet, about 1,000 for a stray whole memory, which 10% of in-domain
  memory-less prompts reach and off-topic prompts almost never do. Every
  comparison query had a matching memory, so these costs are not in the table.
  At a guessed 15% of prompts having a memory, the average is about 200 tokens per
  prompt, and an injected memory stays in the conversation.
- **A miss relies on the names alone.** The catalogue's names are the only fallback
  when nothing is injected. With it 99% of facts reached the model (98% with the
  full index kept, 100% for the forced default, which always reads a file) and 89%
  reached the answer (89% and 90%).
- **`MEMORY.md` and Claude's memory writer.** When Claude saves a memory it adds a
  line to `MEMORY.md`; the catalogue is regenerated by rerunning the command.
- The result depends on how the comparison models "opens a file when it needs to":
  with a more diligent reader the default improves toward 90%, and the catalogue's
  advantage narrows to the token saving. The comparison against `default_read`
  does not depend on that.
- Thresholds and the 0.76 / 0.70 split are calibrated on EmbeddingGemma 2 at 256
  dimensions over 83 memories.

## Evidence

- `bench/results/compare-memory-dev-open.*`, `compare-memory-heldout-open.*`,
  `compare-memory-dev-slim.*`, `compare-memory-heldout-slim.*`,
  `compare-memory-heldout-injection.*`, `retrieval-variants.*`; reproduce with
  `bench/compare.sh` and `bench/variants.sh`. Re-print any with `recall-compare
  render`.
- Ground truth: `queries/facts.json` (98 facts, dev), `queries/heldout-facts.json`
  (117 facts, held-out). Each fact is a verbatim string in its file and each
  question has a body-only fact; both checked by an independent script.
- The held-out set is only held out for the settings chosen here; the 0.70 / 0.76
  split was picked after seeing which held-out queries the old gate dropped, and
  then validated end to end on both sets. A third, untouched set would be the next
  honest check.
- Runs are single, at `--effort low`; the same `default_read` scored 85% and 88% on
  the held-out set twice.
- One benchmark server answered queries in about 3 s with 27 cores busy when
  unpinned on a machine at load average 54, and in 13 ms when pinned to 8 CPUs at
  `nice -n 19`. Cause unconfirmed (CPU contention among spinning threads is the
  suspect); the drivers accept `CPUSET`.

## Revisit when

- A third query set, or real prompts logged for a few weeks, disagrees with the
  58-query result or shows what share of prompts have a matching memory.
- The memory count grows enough that the catalogue itself is costly (it is about 9
  tokens per memory: 780 tokens at 83, 4,500 at 500).
- Claude Code changes how it loads or writes `MEMORY.md`.
- A different embedding model or dimension count is used: re-run
  `recall-experiment` and `recall-bench gate` to recalibrate 0.70 and 0.76.
- Skills get the same treatment: the skills result (95% right source, 74% of facts,
  one sixth of the tokens) has not been rerun with tiered injection.
