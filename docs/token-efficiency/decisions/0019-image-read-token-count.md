---
id: "0019"
host: ali-desktop
date: 2026-11-12T05:55:00Z
finding: 2026-11-12-ali-desktop#2
decision: build
reason: "Read's token figure counts image results as base64 bytes; PNG screenshots were 88% of Read result bytes, so Read is overstated by roughly an order of magnitude"
metric: { question: tool-result-size, key: Read, baseline: 10583912.5, unit: tokens/week }
acted_on: null
outcome: null
outcome_review: null
---
Read rose from 1.8M tokens/week (decision 0004 baseline) to 10.6M on fewer calls, with a
mean result of 94 KB and a maximum of 680 KB, above what a text Read can return. A
per-extension aggregate of the week's local transcripts found 338 PNG Reads holding 88% of
Read result bytes; text Reads averaged 3–6 KB. Image blocks are billed by their pixel
count, so bytes / 4 is the wrong estimate for them.

Decision 0004's verdict `ineffective` therefore rests on the artefact and should be
re-measured on text Reads only once this lands. The fix is in the ledger: count image
results from their dimensions and report them apart from text results, so
tool-result-size ranks real tokens.
