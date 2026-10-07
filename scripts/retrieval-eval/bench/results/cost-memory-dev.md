## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| default_read | 0.0 | 5176 | 30% | 86% | 7% |
| recall_all | 23.8 | 825 | 92% | 93% | 91% |
| default_open | 0.0 | 4672 | 30% | 86% | 7% |
| recall_auto_open | 23.5 | 913 | 88% | 93% | 86% |
| hybrid_open | 23.5 | 4791 | 88% | 93% | 86% |
| slim_open | 23.5 | 1623 | 88% | 93% | 86% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | …read from cache | …written to cache | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|---|---|
| default_read | 100% | 100% | 91% | 71% | 22403 | 0 | 0 | 732 | 7075 | 0.0413 |
| recall_all | - | 92% | 83% | 64% | 4407 | 0 | 0 | 681 | 5718 | 0.0244 |
| default_open | - | 89% | 84% | 57% | 19024 | 0 | 0 | 717 | 6924 | 0.0285 |
| recall_auto_open | - | 92% | 84% | 68% | 4835 | 0 | 0 | 627 | 5607 | 0.0256 |
| hybrid_open | - | 96% | 87% | 68% | 12354 | 0 | 0 | 607 | 5397 | 0.0257 |
| slim_open | - | 100% | 90% | 68% | 6466 | 0 | 0 | 633 | 5188 | 0.0254 |
