# What else was tried on retrieval (spec 006), and why none of it shipped

Written 2026-10-10. The decision record is [ADR 0039](../../../../docs/adr/0039-do-not-add-more-retrieval-machinery-to-the-memory-hook.md);
this file holds the numbers. Everything below was tried after the short skill listing and
512 dimensions (ADR 0038) and did not earn a place in the hook:

| tried | result | where |
|---|---|---|
| example-question vectors | ranking up, gate unchanged | below |
| skill-consensus blend | within noise, top-1 worse | below |
| embedding parts of a prompt | worse than the whole prompt | below |
| the previous prompt as query context | one sample better, one not | real typed prompts |
| cavemem as the memory source | 6% of needed facts in context | compare-memory.md |
| a paragraph of the memory under the best snippet | +3 of 58 labelled prompts for +79 tokens on every prompt | outcome test |

The first sections concern skill sections: measured on the shortened skills tree
(160-character descriptions, 839 sections, 41 skills), 512 dims, `skill-recall
calibrate` with the dev (20) and held-out (30) skills sets and the 30 off-topic prompts.
Neither question vectors nor the consensus blend changes the recall against
false-injection tradeoff enough to ship.

## Example-question vectors

Haiku wrote 4 example user messages per section from the section text alone (the query
sets were never shown to it). Each question is embedded as an extra vector that scores as
its section (best of section and questions). 1,778 extra chunks; indexing 181 s to 251 s.

Ranking (`retrieval-eval`, sections only):

| set | questions | R@1 | R@3 | R@5 | MRR |
|---|---|---|---|---|---|
| held-out | no | 0.67 | 0.87 | 0.90 | 0.757 |
| held-out | yes | 0.77 | 0.90 | 0.97 | 0.838 |
| dev | no | 0.65 | 0.90 | 0.90 | 0.759 |
| dev | yes | 0.65 | 0.85 | 0.90 | 0.771 |

At the gate (recall of the right section in the top 3 against off-topic false injections):

| set | plain | with questions |
|---|---|---|
| held-out | 0.72: 80% recall, 27% false | 0.78: 80% recall, 27% false |
| dev | 0.72: 85% recall, 27% false | 0.78: 80% recall, 27% false |
| held-out | 0.74: 63% recall, 17% false | 0.80: 70% recall, 10% false |
| dev | 0.74: 70% recall, 17% false | 0.80: 60% recall, 10% false |

A question is short like a prompt, so its cosine with a prompt is higher than a
prompt's with a section body: every score moves up about 0.06 and off-topic prompts
rise with them. At equal false-injection rates the recall is the same or worse; ranking
improves but the gate does not. Not shipped.

## Skill consensus

A section's score blended with the best other section of the same skill,
`(own + alpha * best_other) / (1 + alpha)`, on the plain index.

| alpha | dev recall / false inj. at 0.72 | held-out recall / false inj. at 0.72 |
|---|---|---|
| 0 | 85% / 27% | 80% / 27% |
| 0.25 | 75% / 20% | 80% / 20% |
| 0.5 | 75% / 20% | 77% / 20% |
| 1.0 | 75% / 20% | 70% / 20% |

Plain scores interpolate to about 77% (dev) and 71% (held-out) recall at 20% false, so
alpha 0.25 is within noise on dev (+-2) and about +9 on held-out, while top-1 accuracy
drops (67% to 57%). With 20 and 30 queries that is 1 to 3 queries; not shipped.

## Long prompts, and embedding parts of them

The query sets are one line; real prompts are several sentences. Haiku expanded the 30
held-out queries (same need, same expected section) and the 30 off-topic prompts into
81 to 112 word messages with situational context. Plain index, `skill-recall calibrate`:

| embedded | 0.70 recall / false inj. | 0.72 | 0.74 (old shipped) | 0.76 |
|---|---|---|---|---|
| whole prompt | 90% / 23% | 87% / 10% | 83% / 3% | 63% / 0% |
| last sentence | 53% / 47% | 43% / 23% | 33% / 10% | 20% / 3% |
| best of the sentences | 73% / 73% | 73% / 43% | 67% / 13% | 60% / 3% |
| whole prompt and sentences | 80% / 73% | 80% / 47% | 77% / 13% | 70% / 3% |

The whole prompt wins at every threshold: context is signal, and a lone sentence
resembles unrelated sections. Whole long prompts also separate better than the
one-line queries do (87% recall at 10% false injections at 0.72, against 80% at 27%),
so the one-line sets understate what the shipped 0.72 skills floor does on real prompts.
Caveat: the long prompts are model-written, cleaner than typed ones. Not shipped.

### Memory, same test

The 30 held-out memory queries expanded the same way (`recall-bench gate`, 512 dims,
86 memories, off-topic prompts long too; adjacent prompts not expanded, so adjacent false
injections are not measured for the long set):

| prompt | 0.70 | 0.72 | 0.74 (shipped full-body floor) | 0.76 |
|---|---|---|---|---|
| one line | 90% / 3% / 75% | 90% / 3% / 87% | 83% / 3% / 89% | 60% / 0% / 95% |
| long | 100% / 3% / 97% | 100% / 3% / 97% | 93% / 0% / 100% | 93% / 0% / 100% |

(recall / off-topic false injections / precision.) Top-1 score of the right memory:
long prompts min 0.732, median 0.806; off-topic long prompts max 0.726. The two
distributions barely touch, where the one-line sets overlap (relevant min 0.688,
off-topic max 0.741). The recall target of 90% (SC-007) is met by long prompts at the
shipped floors; the one-line set is the pessimistic case. Caveat as above: model-written
prompts are cleaner than typed ones, so the truth lies between the two sets.

## Real typed prompts (memory gate), the pessimistic and probably truest case

Human-typed prompts from past sessions of this project (`origin.kind == "human"` in the
transcripts, pasted blocks removed, 25 to 1,500 characters). Two non-overlapping random
samples (90 and 120 prompts, the current session excluded). A model labelled, from the
memory descriptions alone, which memory files would materially help each prompt (strict:
topical overlap is not enough; most prompts get none). 29 prompts in each sample had a
memory. 512 dims, whole prompt as the query, `recall-bench gate`:

| sample | floor | recall | off-topic false inj. | precision |
|---|---|---|---|---|
| 1 (29 / 61) | 0.70 | 45% | 48% | 27% |
| 1 | 0.72 | 38% | 21% | 35% |
| 1 | 0.74 (full-body floor) | 17% | 8% | 33% |
| 2 (29 / 91) | 0.70 | 66% | 40% | 33% |
| 2 | 0.72 | 52% | 22% | 38% |
| 2 | 0.74 | 38% | 10% | 50% |

Right-memory top-1 score: median 0.732 and 0.737; off-topic top-1 maximum 0.762 and
0.779, so the distributions overlap, unlike the model-written long prompts. Ranking:
R@3 0.62 (sample 1) and 0.79 (sample 2). Most misses are short follow-ups that only
mean something in the conversation ("run the scale-up test please", "cursor at the right
edge atm", "can you unlock that please"). Labels are one model's judgement from
descriptions, so some "false injections" are memories that were topical but judged not
needed; treat the false-injection column as an upper bound.

Adding conversation context to the query (the previous human prompt, read from the
transcript, prepended to the prompt):

| sample | query | R@3 | MRR | recall / false inj. at 0.72 | at 0.74 |
|---|---|---|---|---|---|
| 1 | prompt | 0.62 | 0.532 | 38% / 21% | 17% / 8% |
| 1 | + previous prompt | 0.62 | 0.586 | 48% / 36% | 38% / 11% |
| 1 | + previous two prompts | 0.55 | 0.538 | 48% / 39% | 31% / 15% |
| 1 | + last assistant text | 0.59 | 0.557 | 48% / 59% | 45% / 31% |
| 2 | prompt | 0.79 | 0.701 | 52% / 22% | 38% / 10% |
| 2 | + previous prompt | 0.79 | 0.700 | 55% / 35% | 45% / 18% |

The previous prompt helped on sample 1 (recall 17% to 38% at 0.74, off-topic false
injections 8% to 11%) and did not on sample 2 (same MRR, same R@3, more false
injections at every floor). Not reproduced, so not shipped. Assistant text raises the
off-topic scores as much as the relevant ones.

### The hook against the default flow, same 58 labelled prompts

The default flow was simulated: a sonnet agent saw only the index and one prompt and
named up to 3 memory files it would open (88 prompts: the 58 above plus 30 that need no
memory). Two index shapes: names only (what `MEMORY.md` is now) and a line per file with
its description (the older default).

| flow | right memory reached (of 58) | no-memory prompts that opened something (of 30) | files opened per prompt |
|---|---|---|---|
| model picks, names-only index | 47 (81%) | 11 | 1.4 |
| model picks, name and description index | 50 (86%) | 3 | 1.1 |
| hook alone, floor 0.68 / 0.70 / 0.74 | 38 / 32 / 17 (66 / 55 / 29%) | | 0 (injects a line) |
| names-only picks plus hook at 0.68 / 0.70 / 0.74 | 50 / 49 / 48 (86 / 84 / 83%) | | |

On real prompts the hook alone reaches the right memory far less often than a model
choosing from the index, and on top of the names-only catalogue it adds 3 of 58 (0.68),
2 (0.70) or 1 (0.74). Caveats that favour the default: the labels were made from the
descriptions by a model, so the description-index arm is close to the labeller itself;
the picks are what a model says it would open, not what it opens (a read costs about
1,000 tokens, an injected line about 35); and each prompt was judged without its
conversation. What the hook buys is not recall over the catalogue but the read it saves
and the memory the model would not have opened. This table overstates the default: see
"What the model actually opened" below, where the picks turn out to be almost never made.

### What the model actually opened

The comparison above uses a simulated model that says which files it would open. The
transcripts of the 1,562 prompts typed in past sessions record what it did: a memory file
was opened (`Read` on a path in the memory directory, main thread) on 52 prompts (3.3%),
and on 32 of the 1,142 prompts before the hook existed (2.8%). Of the 59 labelled prompts
where a memory would materially help, 57 came before the hook; the labelled memory was
opened on none of them, and no memory at all on any. `Bash` calls touching the memory
directory add at most a few more and many of them are writes.

So the simulated 81% for the names-only index overstates the default: the default
delivers a memory's text almost never, and has only what the index line says. In the
benchmark an index with no read put 31% of the facts in context and 39% in the answer,
against 92% and 83% for the hook with the file read. Whether the 57 prompts needed the
text is unknown: the answers may have been fine, and an index line can carry the fact
(86% of the benchmark facts sat in descriptions). The outcome test below measures it.

### Does the injected text change the answer? (outcome test)

The 58 labelled prompts where a memory would help, each answered by sonnet with no tools
in a clean directory, with the descriptive `MEMORY.md` index in its system prompt and:

- **A**: nothing more (the default: Claude opens a memory on about 3% of prompts);
- **B**: what the hook injects at the floors in use (0.68 snippets, 0.74 whole memory);
- **C**: the labelled memory in full (the ceiling);
- **D**, **E**: B with the one-line snippet of a hit replaced by the paragraph of that
  memory closest to the prompt (D: every snippet, up to 700 characters; E: only the best
  snippet, cut at 450);
- **F**: E implemented in the hook (`memory-recall hook`, pieces from `split_body_chunks`);
  PR #554, closed unmerged, holds the code.

A separate sonnet call, shown the prompt, the note and the answers shuffled, said for each
answer whether it states or acts on a specific fact from the note that matters for the
prompt (generic advice, a guess or "I would need to look it up" count as no) and whether it
contradicts the note. Answers that used a fact, of 58:

| judged together | A | B | D | E | F | C |
|---|---|---|---|---|---|---|
| A, B, C (first pass) | 27 | 33 | | | | 57 |
| A, B, C, D | 24 | 31 | 38 | | | 57 |
| B, D, E, C | | 32 | 40 | 38 | | 57 |
| B, E, F, C, three passes | | 38 / 37 / 36 | | 40 / 38 / 39 | 41 / 41 / 39 | 57 |
| B, E, F, C, majority of the three | | 37 | | 39 | 40 | 57 |

Two readings. The whole note gets the fact into 57 of 58 answers, against 24 to 27 for
the index alone: the text matters. The hook's one-line snippet adds little to the index
(it repeats the description line `MEMORY.md` already carries): for the 22 prompts where the
right memory reached the answer only as a snippet, A used the fact in 10, B in 11, D in
18 and C in 21; for the 15 where it was injected whole, B used it in 14 or 15 of 15. The
paragraph recovers part of that gap.

The size of the gain is smaller than the first passes suggested. The same B answers scored
31 to 38 depending on which other answers shared the judging call, so a single pass
exaggerates gaps; within the three passes over identical answers F beat B by 3, 4 and 3,
and E by 2, 1 and 3, so the excerpt is worth about 3 of 58 labelled prompts
(5 points of them). Contradictions of the note, per pass: B 4, 2, 3; E 5, 3, 5; F 2, 2, 2;
C 1, 3, 1. Injected text over the 58 prompts: B 437 tokens, E 518, F 527 (D 639).

The 21 prompts where the hook never retrieved the right memory are unchanged (A 5, B 6,
D 6, C 21): the paragraph cannot help what was not found.

Caveats: model-judged, 58 prompts, the labels come from the descriptions, and "used a
fact" is not "gave a better answer".

### What the excerpt costs on an ordinary prompt, and the verdict

The 58 prompts all need a memory, so they overstate how often an excerpt is added. Over
all 210 typed prompts sampled (the 58 plus 152 that need none), with the hook built from
the excerpt commits, `--excerpt-chars 450` against `--excerpt-chars 0`, same cache and
floors:

| | without | with |
|---|---|---|
| prompts that get any memory text | 154 of 210 (73%) | 154 |
| prompts that get an excerpt | | 149 of 210 (71%) |
| mean injected tokens per prompt | 254 | 332 |

That is +79 tokens on every prompt (+31% of what the memory hook adds), about 111 where
it fires, for roughly 3 more used facts per 58 labelled prompts. Those 58 are 28% of the
sample, so about 1.5 extra uses per 100 prompts for about 7,900 extra tokens per 100
prompts: around 5,000 tokens per extra use, against about 1,000 for reading the whole
note. **Not adopted**: the code (PR #554) was closed unmerged. The sample is mostly
in-domain repository chat, so the 71% is high for general use, but it is how this
machine is used.

The generators, the `--questions`, `--consensus` and `--prompt-mode` flags, the
generated `questions.json` files and the outcome-test scripts were not merged; only these
results and the method above are kept. The typed prompts and their labels are private
and not in the repository.
