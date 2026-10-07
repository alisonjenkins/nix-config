## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| none | 0.0 | 0 | 0% | 0% | 0% |
| default_skill_only | 0.0 | 6813 | 2% | 0% | 2% |
| default_load | 0.0 | 8872 | 2% | 0% | 2% |
| sections_bm25 | 0.1 | 903 | 54% | 0% | 54% |
| sections_embed | 13.7 | 652 | 88% | 0% | 88% |
| oracle | 0.0 | 373 | 100% | 0% | 100% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | …read from cache | …written to cache | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|---|---|
| none | - | 0% | 20% | 0% | 2946 | 0 | 0 | 603 | 5943 | 0.0178 |
| default_skill_only | 20% | 28% | 22% | 5% | 21302 | 0 | 0 | 519 | 6259 | 0.0462 |
| default_load | 95% | 95% | 72% | 30% | 36972 | 0 | 0 | 621 | 8506 | 0.0873 |
| sections_bm25 | 65% | 54% | 52% | 35% | 4284 | 0 | 0 | 452 | 4284 | 0.0216 |
| sections_embed | 95% | 88% | 70% | 35% | 3924 | 0 | 0 | 460 | 4056 | 0.0195 |
| oracle | 100% | 100% | - | - | - | - | - | - | - | - |
