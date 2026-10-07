## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| slim_open | 91.6 | 1773 | 85% | 93% | 83% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|
| slim_open | - | 99% | 88% | 63% | 7236 | 676 | 5779 | 0.0357 |
