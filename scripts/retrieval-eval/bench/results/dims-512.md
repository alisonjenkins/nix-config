# 512 dimensions instead of 256 (spec 006)

Same embedding model (EmbeddingGemma 2 Q8_0), Matryoshka dimensions 256 or 512,
`recall-bench gate` on the live memory directory with the dev, held-out and third
query sets, and `skill-recall calibrate` and `retrieval-eval` on the shortened skills
tree with the dev and held-out skills sets. Each memory query set also scores 30
off-topic and 20 adjacent prompts.

## Memory gate (injection threshold applied to the top memory, top 3)

| dims | threshold | recall dev / held-out / third | false inj. off-topic / adjacent | precision dev / held-out / third | tokens per prompt |
|---|---|---|---|---|---|
| 256 | 0.70 | 93 / 93 / 97% | 17% / 65% | 57 / 58 / 60% | 104 |
| 256 | 0.74 (shipped) | 93 / 90 / 83% | 3% / 20% | 84 / 82 / 83% | 49 |
| 256 | 0.76 | 89 / 83 / 80% | 0% / 10% | 93 / 89 / 89% | 32 |
| 512 | 0.70 | 93 / 90 / 93% | 3% / 35% | 72 / 75 / 78% | 68 |
| 512 | 0.72 | 93 / 90 / 87% | 3% / 10% | 90 / 87 / 90% | 47 |
| 512 | 0.74 | 89 / 83 / 80% | 3% / 5% | 93 / 89 / 89% | 34 |

At 512 dimensions the same recall comes with half the adjacent-prompt false injections
(0.72 against the old 0.74) and 6 to 7 points more precision, at the same tokens per
prompt. 512 scores sit a little lower, so the full-memory score moves from 0.76 to 0.74
and the snippet floor stays at 0.70.

## Skills retrieval (shortened tree, no model calls)

| dims | dev R@1 / R@3 | held-out R@1 / R@3 |
|---|---|---|
| 256 | 0.55 / 0.85 | 0.70 / 0.80 |
| 512 | 0.65 / 0.90 | 0.67 / 0.87 |
| 768 | 0.65 / 0.85 | 0.70 / 0.83 |

Fusing BM25 with the dense scores lowered top-3 recall on the dev set (0.80 against
0.90 for dense alone) and is not used.

## Skills floor sweep (512 dimensions, shortened tree, top 3)

| threshold | recall dev / held-out | false inj. off-topic | tokens per prompt if every hit were in full |
|---|---|---|---|
| 0.66 | 90 / 87% | 70% | 457 / 356 |
| 0.68 | 90 / 87% | 60% | 427 / 326 |
| 0.70 | 85 / 87% | 43% | 360 / 281 |
| 0.72 | 85 / 80% | 27% | 305 / 221 |
| 0.74 | 70 / 63% | 13% | 162 / 140 |

The shipped setting is 0.72 for a full section and 0.66 for a one-line pointer, so
the 70% of off-topic prompts that clear 0.66 cost about 30 tokens a pointer rather
than 750 for a section.
