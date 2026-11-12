---
review: 2026-11-12-ali-desktop
host: ali-desktop
period: 2026-11-05/2026-11-12
pack_version: 1
own_cost_usd: 3
---
own_cost_usd is an estimate (about 20 main-loop requests at 60–90k context on Opus); the stack had no review-run samples. Totals: 98 sessions, 23.5M new tokens, est. $1,149 at list price; claude-opus-5-5 88.7% of spend, claude-sonnet-5-5 10.5%; fixed context 57.1% of each request. Gaps: 42 sub-agent runs left no transcript; 1466 duplicate tool_call records ignored by the repeats questions.

## 1. Long sessions re-read huge contexts — est. saving $70–100/week if 0012 does not already deliver it
Evidence: costly-sessions session:554fed0b-d6f3-5393-a783-582cc1ef366c ($137, 12% of spend, 782 requests, 9 compactions, per-turn context 180k–310k, cache hit 0.99); session:9cc8bc72-1b5b-5108-b53f-a3fae2c8574f ($114, 10%, 951 requests, context up to 317k). Recurs from 2026-10-25-ali-desktop#1 at more than twice the spend. Suggested action: dismiss (covered by decision 0012, autoCompactWindow 200000, live since 2026-11-11T12:02Z; re-measure next review). Status: proposed

## 2. Read token figure counts image results as base64 bytes — instrument fix, no direct saving
Evidence: tool:Read 451 calls, mean result 94 KB, max 680 KB, 10.6M tokens (63% of tool-result tokens). A per-extension aggregate of the week's local transcripts put PNG at 338 Reads and 88% of Read result bytes (mean 232 KB); text Reads averaged 3–6 KB. Image blocks are billed by pixel count, not bytes / 4, so the figure overstates Read by roughly an order of magnitude, and decision 0004's verdict `ineffective` is a measurement artefact. Suggested action: build-tool (ledger counts image results by dimensions, reported separately from text). Status: proposed

## 3. Screenshots stay in context — est. saving 0.5–1.5M tokens/week
Evidence: 338 PNG Reads in the week (transcript aggregate, references only); at roughly 1.6k–4.8k tokens each they are re-read from cache on every later request of the session. Suggested action: configure (screenshots only the model reads at deviceScaleFactor 1, clipped to the element under test; say so in the web-ui skill). Status: proposed

## 4. Sonnet general-purpose sub-agent spend doubled — est. saving $40–50/week
Evidence: delegation-tier-fit subagent:general-purpose@claude-sonnet-5-5 $111.6/week (83% of sub-agent spend), against the $49.8 baseline of decision 0001. Suggested action: configure (route mechanical steps to the Gemini rung or haiku-worker; keep Sonnet for steps whose design is open). Status: proposed

## 5. Script candidates — est. saving under $7/week each
Evidence: script-candidates shape:sed $6.3, shape:sed [cd] $5.6, shape:python3 [heredoc] $5.3, shape:python3 [-c] $4.7. Suggested action: dismiss for now (revisit once the larger items are acted on). Status: proposed
