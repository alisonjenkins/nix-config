## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| default_read | 0.0 | 5210 | 18% | 73% | 10% |
| recall_all | 90.5 | 1043 | 89% | 93% | 88% |
| default_open | 0.0 | 4879 | 18% | 73% | 10% |
| recall_auto_open | 90.4 | 1034 | 85% | 93% | 83% |
| hybrid_open | 90.4 | 4944 | 85% | 93% | 83% |
| slim_open | 90.4 | 1851 | 85% | 93% | 83% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | …read from cache | …written to cache | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|---|---|
| default_read | 100% | 100% | 89% | 70% | 22500 | 0 | 0 | 644 | 6556 | 0.0463 |
| recall_all | - | 89% | 82% | 60% | 4809 | 0 | 0 | 622 | 5030 | 0.0254 |
| default_open | - | 81% | 74% | 47% | 19255 | 0 | 0 | 655 | 6254 | 0.0266 |
| recall_auto_open | - | 91% | 79% | 50% | 4935 | 0 | 0 | 568 | 4675 | 0.0254 |
| hybrid_open | - | 93% | 80% | 57% | 12647 | 0 | 0 | 559 | 4832 | 0.0265 |
| slim_open | - | 97% | 83% | 53% | 7067 | 0 | 0 | 594 | 5096 | 0.0274 |
