## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| default_read | 0.0 | 5186 | 18% | 73% | 10% |
| recall_all | 91.1 | 1043 | 89% | 93% | 88% |
| default_open | 0.0 | 4666 | 18% | 73% | 10% |
| recall_auto_open | 91.0 | 943 | 85% | 93% | 83% |
| hybrid_open | 91.0 | 4908 | 85% | 93% | 83% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|
| default_read | 100% | 100% | 88% | 67% | 15419 | 736 | 7254 | 0.0333 |
| recall_all | - | 89% | 79% | 57% | 4806 | 745 | 6118 | 0.0192 |
| default_open | - | 81% | 74% | 43% | 19030 | 869 | 8780 | 0.0595 |
| recall_auto_open | - | 91% | 80% | 57% | 4920 | 715 | 6233 | 0.0268 |
| hybrid_open | - | 97% | 86% | 60% | 13361 | 674 | 5616 | 0.0602 |
