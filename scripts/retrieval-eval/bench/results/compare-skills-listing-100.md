## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| default_skill_only | 0.0 | 3413 | 0% | 0% | 0% |
| default_load | 0.0 | 4318 | 0% | 0% | 0% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | …read from cache | …written to cache | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|---|---|
| default_skill_only | 20% | 25% | 25% | 5% | 12584 | 2839 | 9741 | 729 | 10227 | 0.0468 |
| default_load | 75% | 75% | 58% | 25% | 21463 | 4342 | 17115 | 792 | 13682 | 0.0773 |
