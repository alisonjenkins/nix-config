---
id: "0013"
host: Alisons-MacBook-Pro
date: 2026-11-11T10:13:30Z
finding: 2026-11-11-Alisons-MacBook-Pro#2
decision: configure
reason: "cc-obs-query's compaction and tool-result queries selected service_name=\"claude-code\", but the client actually exports service_name=\"claude-code-desktop\"; neither question ever matched a real log line"
metric: { question: compaction-frequency, key: sessions-with-compaction-samples, baseline: 1, unit: sessions/week }
acted_on: null
outcome: null
outcome_review: null
---
`compaction-frequency` returning `"unavailable":"no samples for compaction events in the window"` was a collector-side name mismatch, not zero compactions. Claude Code's desktop-app client exports its OTel resource attribute as `service.name=claude-code-desktop` (confirmed directly against the running Loki instance: `service_name` values present are `cc-obs-ledger`, `claude-code-desktop`, `skill-recall` — never bare `claude-code`). `cc-obs-query`'s `top session --by compactions` ([top.rs](../../../scripts/token-tools/cc-obs-query/src/commands/top.rs)) and `top tool` ([tool.rs](../../../scripts/token-tools/cc-obs-query/src/commands/tool.rs)) both built their LogQL selector against the literal `"claude-code"`, so neither query ever matched a log line — explaining why this same digest's `tool-result-size` question came back empty too, despite clear tool activity elsewhere.

The collector pipeline, Loki ingestion (structured metadata, OTLP `/otlp/v1/logs` path) and the `event_name`/field names in `questions.yaml`'s `signals:` list were all already correct; only the service-name selector was wrong. Fixed by matching any `claude-code` client variant (`service_name=~"claude-code(-.+)?"`) in both `cc-obs-query` and the `claude-code.json` Grafana dashboard, since the CLI and desktop app (and potentially future clients) report different suffixes for the same product.

Verified against the live stack (not a quick synthetic test — real retained logs): the patched binary now finds 24 compaction events across 10 sessions and full tool_result data for the 30-day window, where the deployed binary found 1 and 0 respectively.

One open item this fix does not resolve: the specific session that prompted this investigation (`7371dd92-bd49-4022-9c8c-72a4658fac0b`, agent-context-growth +544,164 tokens) has no `api_request`/`tool_result`/`compaction` events in Loki at all — only startup-type events (`plugin_loaded`, `hook_registered`, `hook_execution_*`, `managed_settings_resolved`). Its context-growth number came from `cc_obs_ledger_context_tokens` (transcript-derived, independent of Claude Code's own OTel export), so whether *that* session compacted at the 350k threshold remains unconfirmed — a session-specific gap, not the service-name bug this decision fixes. A future review should flag it again if it recurs.
