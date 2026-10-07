## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| default_read | 0.0 | 5194 | 30% | 86% | 7% |
| default_open | 0.0 | 4649 | 30% | 86% | 7% |
| hybrid_open | 23.7 | 4811 | 88% | 93% | 86% |
| slim_open | 23.7 | 1603 | 88% | 93% | 86% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | …read from cache | …written to cache | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|---|---|
| default_read | 100% | 100% | 92% | 75% | 22435 | 14644 | 7787 | 712 | 7280 | 0.0412 |
| default_open | - | 89% | 85% | 61% | 19166 | 13536 | 5626 | 581 | 7199 | 0.0417 |
| hybrid_open | - | 100% | 92% | 71% | 12804 | 8338 | 4464 | 576 | 5564 | 0.0271 |
| slim_open | - | 96% | 91% | 79% | 6276 | 1853 | 4420 | 595 | 5199 | 0.0251 |
