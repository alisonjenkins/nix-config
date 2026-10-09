## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| default_skill_only | 0.0 | 7360 | 2% | 0% | 2% |
| default_load | 0.0 | 9384 | 2% | 0% | 2% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | …read from cache | …written to cache | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|---|---|
| default_skill_only | 20% | 29% | 26% | 5% | 22412 | 10134 | 12274 | 520 | 9852 | 0.0563 |
| default_load | 95% | 95% | 80% | 40% | 39015 | 16095 | 22914 | 549 | 11364 | 0.1004 |
