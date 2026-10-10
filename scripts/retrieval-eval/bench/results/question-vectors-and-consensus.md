# Example-question vectors and skill consensus (spec 006) — no gain at the gate

Two ways to separate relevant skill sections from off-topic prompts, measured on the
shortened skills tree (160-character descriptions, 839 sections, 41 skills), 512 dims,
`skill-recall calibrate` with the dev (20) and held-out (30) skills sets and the 30
off-topic prompts. Neither changes the recall against false-injection tradeoff enough to
ship.

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

The generator, the `--questions` and `--consensus` flags and the generated
`questions.json` files were not merged; only these results are kept.
