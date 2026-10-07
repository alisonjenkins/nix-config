## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| default_read | 0.0 | 5313 | 18% | 73% | 10% |
| default_open | 0.0 | 4702 | 18% | 73% | 10% |
| hybrid_open | 90.1 | 4989 | 85% | 93% | 83% |
| slim_open | 90.1 | 1819 | 85% | 93% | 83% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | …read from cache | …written to cache | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|---|---|
| default_read | 100% | 100% | 86% | 60% | 22681 | 14644 | 8033 | 657 | 7605 | 0.0416 |
| default_open | - | 80% | 71% | 40% | 18742 | 13031 | 5707 | 536 | 8334 | 0.0407 |
| hybrid_open | - | 95% | 83% | 60% | 13095 | 8152 | 4941 | 518 | 5548 | 0.0283 |
| slim_open | - | 97% | 84% | 60% | 7066 | 2219 | 4845 | 587 | 5896 | 0.0281 |
