## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| default_skill_only | 0.0 | 6550 | 2% | 0% | 2% |
| default_load | 0.0 | 7737 | 2% | 0% | 2% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | …read from cache | …written to cache | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|---|---|
| default_skill_only | 20% | 28% | 25% | 0% | 20563 | 9002 | 11558 | 637 | 9157 | 0.0544 |
| default_load | 85% | 85% | 74% | 45% | 34703 | 14296 | 20401 | 614 | 10464 | 0.0906 |
