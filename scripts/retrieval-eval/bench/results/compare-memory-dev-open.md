## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| default_read | 0.0 | 5062 | 30% | 86% | 7% |
| recall_all | 23.4 | 825 | 92% | 93% | 91% |
| default_open | 0.0 | 4684 | 30% | 86% | 7% |
| recall_auto_open | 23.8 | 810 | 88% | 93% | 86% |
| hybrid_open | 23.8 | 4701 | 88% | 93% | 86% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|
| default_read | 100% | 100% | 93% | 79% | 15160 | 829 | 8899 | 0.0410 |
| recall_all | - | 92% | 84% | 64% | 4404 | 763 | 6332 | 0.0252 |
| default_open | - | 90% | 85% | 61% | 19548 | 955 | 9432 | 0.0596 |
| recall_auto_open | - | 92% | 82% | 64% | 4797 | 721 | 6532 | 0.0264 |
| hybrid_open | - | 100% | 93% | 79% | 12712 | 681 | 5968 | 0.0577 |
