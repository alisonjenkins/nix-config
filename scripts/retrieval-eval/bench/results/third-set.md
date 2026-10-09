# Third query set (spec 006, SC-007)

30 queries written after the dev and held-out sets were frozen, from each memory's
one-line description and not its body, one memory per query, paraphrased and not
copied from the description. Run on the live 256-dimension index with
`retrieval-eval --corpus memory` and `recall-bench gate`.

| set | n | R@1 | R@3 | R@5 | MRR | gate recall at 0.70 | at 0.74 | at 0.76 |
|---|---|---|---|---|---|---|---|---|
| dev | 28 | 0.89 | 0.93 | 0.96 | 0.923 | 93% | 93% | 89% |
| held-out | 30 | 0.87 | 0.97 | 0.97 | 0.917 | 93% | 90% | 83% |
| third | 30 | 0.93 | 1.00 | 1.00 | 0.967 | 97% | 83% | 80% |

Ranking agrees with the held-out set (R@3 within 3 points). Recall through the
0.74 gate does not: 83% against 90%, 7 points, which is 2 of 30 queries. Shorter,
paraphrased queries score lower against the same memories, so more of them fall
under the floor. At 0.70 the third set recalls 97%. False injection rates come
from the same 50 negative prompts on every set, so they are not independent
evidence. SC-007 is therefore met for ranking and not met for the shipped gate.
