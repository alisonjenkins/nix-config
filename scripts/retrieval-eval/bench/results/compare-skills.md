## Retrieval stage (deterministic)

| system | local retrieval ms (median/query) | tokens put in context by retrieval | facts in retrieved text | …description facts | …body-only facts |
|---|---|---|---|---|---|
| none | 0.0 | 0 | 0% | 0% | 0% |
| default_skill_only | 0.0 | 6827 | 2% | 0% | 2% |
| default_load | 0.0 | 8763 | 2% | 0% | 2% |
| sections_bm25 | 0.1 | 903 | 54% | 0% | 54% |
| sections_embed | 14.9 | 652 | 88% | 0% | 88% |
| oracle | 0.0 | 373 | 100% | 0% | 100% |

## End to end with the model (isolated `claude -p`)

| system | right source chosen | facts in final context | facts in answer | answers with every fact | model input tokens | model output tokens | model API ms | cost $/query |
|---|---|---|---|---|---|---|---|---|
| none | - | 0% | 16% | 0% | 2946 | 579 | 5824 | 0.0176 |
| default_skill_only | 20% | 28% | 25% | 5% | 15488 | 774 | 8855 | 0.0390 |
| default_load | 95% | 95% | 74% | 40% | 25191 | 949 | 11151 | 0.0800 |
| sections_bm25 | 65% | 54% | 49% | 30% | 4281 | 616 | 5872 | 0.0227 |
| sections_embed | 95% | 88% | 74% | 40% | 3920 | 593 | 5296 | 0.0203 |
| oracle | 100% | 100% | - | - | - | - | - | - |
