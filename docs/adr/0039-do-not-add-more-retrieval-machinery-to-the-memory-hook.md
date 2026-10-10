# 0039. Do not add more retrieval machinery to the memory hook

- Status: Accepted. Research closed 2026-10-10; nothing here is waiting to be built.
- Date: 2026-10-10
- Builds on [0029](0029-embedding-retrieval-for-memory-and-skills.md),
  [0030](0030-inject-confident-memories-and-use-a-catalogue.md),
  [0032](0032-fail-closed-separate-index-server-and-telemetry.md) and
  [0038](0038-shorten-the-skill-listing-at-install-and-cap-injected-tokens.md).

## Context

After the short skill listing (0038) the open question was how far the hook could be
pushed toward finding the right memory and skill section for every prompt, and whether
it beats what Claude does without it. Over two days we tried the ideas that looked most
likely to help, and, more usefully, replaced the benchmark sets with the prompts that
are actually typed. The numbers are in
[`bench/results/question-vectors-and-consensus.md`](../../scripts/retrieval-eval/bench/results/question-vectors-and-consensus.md);
this record is the decision and the lessons, so the experiments are not run again.

## Decision

- **Keep the hook as it is.** Memory: snippets from 0.68, the whole memory from 0.74,
  512 dimensions. Skills: the hook and the short listing (0038). Descriptive
  `MEMORY.md` stays; the names-only catalogue stays off on `ali-desktop`.
- **Cavemem stays off** in Claude Code and opencode.
- **Do not build** any of: example-question vectors, a skill-consensus blend,
  embedding parts of a prompt, the previous prompt or the assistant's text as extra
  query context, or an excerpt of the memory under the best snippet. Each was tried
  and measured (below).
- **Measure memory changes on typed prompts, with the outcome test.** A benchmark made
  of model-written queries overstates recall and a simulated model overstates the
  default. Method: take human-typed prompts from the session transcripts
  (`origin.kind == "human"`), have a model label which memory would materially help,
  answer each with and without the memory, and judge the answers over several shuffled
  passes. The prompts and labels are private and are not committed.

## What was tried

| tried | result | why it does not ship |
|---|---|---|
| Example-question vectors (4 model-written questions per section, 1,778 extra vectors) | Ranking R@1 0.67 to 0.77 held-out | A question is short like a prompt, so every score rises about 0.06 and off-topic prompts rise with it: at equal false injections the recall is the same or worse. Indexing +39% |
| Skill-consensus blend (a section's score mixed with its best sibling's) | Within noise (1 to 3 queries); top-1 67% to 57% | No gain at the gate |
| Embedding parts of a prompt (last sentence, best of the sentences, both) | Last sentence 43% recall at 0.72 against 87% for the whole prompt | Context is signal; a lone sentence resembles unrelated sections |
| Previous prompt prepended to the query | Recall at 0.74 17% to 38% on one sample of typed prompts, no change on the other | Not reproduced. The assistant's text raises off-topic scores as much as relevant ones |
| Cavemem as the memory source | 6% of needed facts in context, 18% in answers, against 9% with no memory; costs more than loading nothing | Wrong tool for retrieving notes by topic |
| A paragraph of the memory under the best snippet (built: PR #554, closed) | Answers that use the memory's fact: 3 more of 58 labelled prompts, three judge passes | +79 tokens on every typed prompt (254 to 332, fires on 71%), about 5,000 tokens per extra use against about 1,000 to read the note |

Earlier work that points the same way is in the 0029 to 0038 records: margin gates, BM25
fusion, other dimension counts.

## What we learned about measuring this

- **Model-written prompts flatter the hook.** One-line benchmark queries gave 83 to 97%
  right source; model-written long prompts looked better still (memory: 93% recall at
  0% false injections at 0.74). Prompts typed in past sessions gave 17 and 38% at 0.74
  and 45 and 66% at 0.70 on two samples (90 and 120 prompts), with the right memory's
  scores overlapping the off-topic ones. Many are short follow-ups ("run the scale-up
  test please") that only mean something in the conversation: 21 of 58 labelled prompts
  never retrieved their memory.
- **A simulated model is not the model.** Asked which memory files it would open from
  the index, a model said the right one for 47 of 58 prompts. The transcripts show a
  memory file opened on 3.3% of 1,562 prompts (2.8% before the hook existed) and on none
  of the 57 pre-hook prompts where a memory was labelled helpful. The default delivers
  a memory's text almost never; it has the index line. That nearly led to switching the
  hook off on a wrong premise (#551, reverted in #553).
- **The memory text does matter.** Of the 58 labelled prompts, answers used a specific
  fact from the note in 57 when the note was injected whole and in 24 to 27 with the
  index alone. Injected whole by the hook (score at least 0.74) it reached 14 or 15 of
  15 prompts. A one-line snippet adds nothing to the index line it repeats (11 against
  10 to 13 of 22 over two judge passes), and 21 of 58 prompts never reach the hook's
  threshold.
- **One judge call is too noisy.** The same answers scored 31 to 38 depending on which
  other answers shared the judging call. Use several passes with different shuffles and
  report them all.
- **Experiments contend with the live server.** A private embedding server pinned to
  four cores at nice 19 still pushed one live hook call past 3 seconds (the keyword
  fallback caught it; nothing blocked). Run one batch at a time and look at the hook log
  afterwards.

## Consequences

- The memory hook delivers the whole note on the fraction of prompts that score 0.74
  or more (17 of 58 labelled prompts) and one-line snippets, which duplicate the
  descriptive index, otherwise. It is cheap and not very powerful; it should not be
  sold as finding the memory for every prompt.
- Further gains have to come from outside this loop: the prompts the hook never
  retrieves (mostly follow-ups), the quality and size of the memories and of
  `MEMORY.md`, or a lower whole-note floor if its token cost is accepted (about 1,000
  tokens per injection).
- The ADR index and the limitations section of `docs/memory-recall.md` point here.

## Evidence

- Results, with every judge pass: `scripts/retrieval-eval/bench/results/question-vectors-and-consensus.md`.
- Closed code: PR #554 (`feat/memory-recall-excerpt`), the excerpt, its tests and its
  `excerptChars` option.
- Related changes: #548 and #549 (skill listing, reliability), #551 and #553 (memory half
  switched off, then back on), `compare-memory.md` and `compare-skills.md` for the
  earlier head-to-heads.
- Transcript mining: the main-thread `Read` calls on files in the memory directory after
  each human-typed prompt.

## Revisit when

- Claude Code or the model opens memory files much more often than 3% of prompts, which
  would make the index alone worth more than the hook.
- A retrieval change raises recall at equal false injections on typed prompts, not on
  model-written ones, and an outcome test shows the answers use the facts.
- Outcome data shows the whole-note tier is worth lowering `bodyScore` for.
- The labelled prompts grow enough (hundreds, not 58) to separate effects of a few
  points from judge noise.
