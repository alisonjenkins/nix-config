## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| none | 0.0 | 0 | 0% | 0% | 0% |
| default_skill_only | 0.0 | 6799 | 2% | 0% | 2% |
| default_load | 0.0 | 8797 | 2% | 0% | 2% |
| sections_bm25 | 0.1 | 903 | 54% | 0% | 54% |
| sections_embed | 13.6 | 652 | 88% | 0% | 88% |
| oracle | 0.0 | 373 | 100% | 0% | 100% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | …read from cache | …written to cache | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|---|---|
| none | - | 0% | 19% | 0% | 2944 | 0 | 2942 | 605 | 5647 | 0.0178 |
| default_skill_only | 20% | 28% | 19% | 5% | 21272 | 11922 | 9346 | 547 | 6853 | 0.0452 |
| default_load | 95% | 95% | 71% | 30% | 36836 | 17883 | 18947 | 643 | 8630 | 0.0858 |
| sections_bm25 | 65% | 54% | 52% | 35% | 4282 | 0 | 4280 | 494 | 4350 | 0.0221 |
| sections_embed | 95% | 88% | 75% | 45% | 3922 | 221 | 3699 | 506 | 4348 | 0.0199 |
| oracle | 100% | 100% | - | - | - | - | - | - | - | - |
