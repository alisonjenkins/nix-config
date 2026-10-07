## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| default_read | 0.0 | 5236 | 18% | 73% | 10% |
| recall_snippet | 90.5 | 117 | 12% | 93% | 0% |
| recall_read | 90.5 | 976 | 12% | 93% | 0% |
| recall_top | 90.4 | 679 | 84% | 93% | 82% |
| recall_all | 91.2 | 1043 | 89% | 93% | 88% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|
| default_read | 100% | 100% | 85% | 63% | 15514 | 763 | 7378 | 0.0473 |
| recall_snippet | - | 12% | 26% | 3% | 3198 | 814 | 8070 | 0.0209 |
| recall_read | 90% | 90% | 79% | 53% | 7740 | 799 | 7774 | 0.0315 |
| recall_top | - | 84% | 76% | 50% | 4175 | 739 | 6301 | 0.0233 |
| recall_all | - | 89% | 81% | 60% | 4806 | 739 | 5967 | 0.0259 |
