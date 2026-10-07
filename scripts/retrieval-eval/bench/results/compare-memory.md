## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| none | 0.0 | 0 | 0% | 0% | 0% |
| default_index | 0.0 | 3905 | 30% | 86% | 7% |
| default_read | 0.0 | 5167 | 30% | 86% | 7% |
| recall_snippet | 25.3 | 112 | 27% | 93% | 0% |
| recall_read | 25.3 | 787 | 27% | 93% | 0% |
| cavemem_raw | 48.6 | 1 | 0% | 0% | 0% |
| cavemem_kw | 95.5 | 115 | 6% | 14% | 3% |
| cavemem_kw_full | 95.5 | 590 | 18% | 46% | 7% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|
| none | - | 0% | 9% | 0% | 2952 | 793 | 8151 | 0.0197 |
| default_index | - | 31% | 39% | 7% | 10128 | 647 | 6271 | 0.0192 |
| default_read | 100% | 100% | 90% | 71% | 15338 | 851 | 9372 | 0.0412 |
| recall_snippet | - | 27% | 35% | 4% | 3163 | 679 | 6626 | 0.0194 |
| recall_read | 93% | 92% | 83% | 64% | 7348 | 817 | 8619 | 0.0305 |
| cavemem_raw | - | 0% | - | - | - | - | - | - |
| cavemem_kw | - | 6% | 18% | 0% | 6248 | 1024 | 10861 | 0.0351 |
| cavemem_kw_full | - | 18% | 24% | 0% | 7101 | 1072 | 10810 | 0.0389 |
