## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| slim_open | 23.5 | 1530 | 88% | 93% | 86% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|
| slim_open | - | 100% | 91% | 71% | 6452 | 663 | 5536 | 0.0324 |
