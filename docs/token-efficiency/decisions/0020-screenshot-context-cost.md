---
id: "0020"
host: ali-desktop
date: 2026-11-12T05:55:00Z
finding: 2026-11-12-ali-desktop#3
decision: configure
reason: "338 screenshots a week stay in context and are re-read on every later request; take model-only screenshots at deviceScaleFactor 1, clipped to the element under test"
metric: { question: not-pack-tracked, key: transcripts:Read:png, baseline: 338, unit: calls/week }
acted_on: "0baf05c1"
outcome: null
outcome_review: null
---
Each screenshot costs roughly 1.6k–4.8k tokens by pixel count, about 0.5–1.5M tokens a week
in all, and every later request of the session re-reads it from cache. The environment
guidance already says to use scale 1 for a screenshot only the model reads; the web-ui
skill does not repeat it or ask for a clip to the element. The lever is that skill text.
The baseline is a call count from the local transcripts because the stack cannot yet tell
image Reads apart (decision 0019); once it can, this moves to tool-result-size.
