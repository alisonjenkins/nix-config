---
review: 2026-10-25-ali-desktop
host: ali-desktop
period: 2026-10-18/2026-10-25
pack_version: 1
own_cost_usd: 0.5
---
own_cost_usd is an estimate (about 10 requests at 35k context); the stack had no review-run samples. Totals: 21 sessions, 17.7M new tokens, est. $305 at list price; fixed context 31.5% of each request (~65k tokens); mean cache hit 0.99. Loki and Tempo showed `down` at the start of the review (first-probe readiness, fixed separately); the repeats questions carried a gap of 7077 duplicate tool_call records.

## 1. Long sessions re-read huge contexts — est. saving $40–60/week
Evidence: costly-sessions session:f0ea4448-3105-4665-afa5-fab77d73afd3 ($77, 25% of spend, 59 turns, 6 compactions); agent-run-length session:01f4b3b4-5b21-4d4e-b2fd-44c657ccb20a (799 requests, context 680k); agent-context-growth session:6b62c72e-f27d-4223-8cca-1622ad91e04f (+939k). Top 5 sessions were 82% of spend. Suggested action: configure (autoCompactWindow 350000; summaries, not raw output, from sub-agents). Status: proposed

## 2. Sub-agents without a model run on Sonnet — est. saving $30–35/week
Evidence: subagent:general-purpose@claude-sonnet-5-5 ($49.8/week, 65% of sub-agent spend; Haiku general-purpose 979k tokens for $8.3 vs Sonnet 1.6M for $49.8), question delegation-tier-fit. Suggested action: configure (CLAUDE_CODE_SUBAGENT_MODEL=haiku; since Claude Code 2.1.251 it ranks below the Agent call's model and the agent's `model:` frontmatter). Status: proposed

## 3. Fixed context re-read on every request — est. saving $15/week
Evidence: fixed:total 0.3153 share, about 65k tokens per request over about 3.7k requests; earlier one-request split: built-in tool schemas 17.8k, MCP 9.5k, settings 9.3k; skills-loaded-unused top rows dataviz 361, claude-api 270, anthropic-skills:docs 257 listing tokens. Suggested action: configure (measure each component with the one-request method before trimming). Status: proposed

## 4. Whole-file Reads — est. saving $5–10/week direct
Evidence: tool:Read 1138 calls, mean 6.4 KB, max 64 KB, 39% of tool-result tokens; tool:Bash 47% of tokens but mean 1.4 KB. Suggested action: configure (ranged Read after Grep in the shared mandate). Status: proposed

## 5. Script candidates — est. saving under $2/week each
Evidence: script-candidates shape:bash 177 calls $1.8/week, shape:sed $1.3, large_then_narrow mcp gateway $0.9; data carries the 7077-duplicate gap. Suggested action: dismiss (revisit after the ledger dedupe). Status: proposed
