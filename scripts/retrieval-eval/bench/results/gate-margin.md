# Margin gate (spec 006, story 9)

A margin gate injects nothing when the best score leads the runner-up by less than
the margin. Produced with `recall-bench gate --margins 0,0.01,0.02,0.03,0.05` on
the live 256-dimension cache, 30 off-topic and 20 adjacent prompts, top 3. Rows
are the thresholds around the shipped 0.74. Dev n=28, held-out n=30, third n=30
relevant prompts (the third set is `third-set.md`).

Margin 0 is the shipped gate. No margin lowers false injections without costing
recall by about as much; raising the threshold to 0.76 does it more cheaply.

## Dev set

| margin | threshold | recall | false inj. off-topic | false inj. adjacent | precision | mean tokens/prompt |
|---|---|---|---|---|---|---|
| 0.00 | 0.70 | 93% | 17% | 65% | 57% | 104 |
| 0.00 | 0.74 | 93% | 3% | 20% | 84% | 49 |
| 0.00 | 0.76 | 89% | 0% | 10% | 93% | 32 |
| 0.01 | 0.74 | 86% | 0% | 15% | 89% | 40 |
| 0.02 | 0.74 | 82% | 0% | 15% | 88% | 37 |
| 0.03 | 0.74 | 75% | 0% | 10% | 91% | 31 |
| 0.05 | 0.74 | 54% | 0% | 5% | 94% | 21 |

## Held-out set

| margin | threshold | recall | false inj. off-topic | false inj. adjacent | precision | mean tokens/prompt |
|---|---|---|---|---|---|---|
| 0.00 | 0.70 | 93% | 17% | 65% | 58% | 100 |
| 0.00 | 0.74 | 90% | 3% | 20% | 82% | 52 |
| 0.00 | 0.76 | 83% | 0% | 10% | 89% | 35 |
| 0.01 | 0.74 | 83% | 0% | 15% | 89% | 40 |
| 0.02 | 0.74 | 80% | 0% | 15% | 89% | 39 |
| 0.03 | 0.74 | 77% | 0% | 10% | 92% | 35 |
| 0.05 | 0.74 | 50% | 0% | 5% | 94% | 21 |

## Third set

| margin | threshold | recall | false inj. off-topic | false inj. adjacent | precision | mean tokens/prompt |
|---|---|---|---|---|---|---|
| 0.00 | 0.70 | 97% | 17% | 65% | 60% | 103 |
| 0.00 | 0.74 | 83% | 3% | 20% | 83% | 47 |
| 0.00 | 0.76 | 80% | 0% | 10% | 89% | 32 |
| 0.01 | 0.74 | 80% | 0% | 15% | 89% | 41 |
| 0.02 | 0.74 | 73% | 0% | 15% | 88% | 37 |
| 0.03 | 0.74 | 73% | 0% | 10% | 92% | 35 |
| 0.05 | 0.74 | 50% | 0% | 5% | 94% | 22 |

## Trial log against the benchmark

Trial log, 41 memory prompts to 2026-10-08: injected on 95%, median best score
0.75, 29% of injections in full. The benchmark's relevant prompts have median 0.79
and its off-topic prompts 0.64. The trial prompts are long and about the project the
memories describe, so they sit between the two; the log has no correctness label
and no runner-up score, so a margin cannot be judged on it.
