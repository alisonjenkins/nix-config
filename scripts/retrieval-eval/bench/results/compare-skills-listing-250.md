## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| default_skill_only | 0.0 | 5063 | 0% | 0% | 0% |
| default_load | 0.0 | 6322 | 0% | 0% | 0% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | …read from cache | …written to cache | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|---|---|
| default_skill_only | 20% | 28% | 20% | 5% | 16769 | 6108 | 10657 | 657 | 10051 | 0.0504 |
| default_load | 80% | 81% | 66% | 30% | 28885 | 9701 | 19178 | 640 | 12452 | 0.0851 |
