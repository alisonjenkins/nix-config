# 0046. Trace delegated agy calls from the wrapper, as children of Claude's tool span

- Status: Accepted
- Date: 2026-10-17

## Context

Gemini delegation (`delegate-to-gemini.sh`) moves work off Claude, but nothing
recorded it: no count of calls, tokens, failures or denials, and no link from a
call to the Claude session and turn that asked for it. The observability stack
already holds Claude Code's own traces, so the question was how to get `agy`
into the same trace.

Facts found on 2026-10-17 (agy 1.2.9, Claude Code 2.1.293):

- `agy` has no OpenTelemetry exporter. SigNoz's guide says so and points at an
  open request, antigravity-cli#366. It has hooks (`~/.gemini/config/hooks.json`:
  `PostToolUse`, `PostInvocation`, `Stop`, `PreToolUse`) whose payloads carry
  no token counts, and the spans built from them have zero duration.
- `agy -p --output-format json` returns the whole call in one object:
  `conversation_id`, `status`, `response`, `duration_seconds`, `num_turns`,
  `usage` (`input_tokens`, `output_tokens`, `thinking_tokens`,
  `cache_read_tokens`, `total_tokens`) and, when a tool was auto-denied,
  `denied_actions: [{"action": "command", ...}]`.
- With `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1`, Claude Code exports
  `TRACEPARENT` to every Bash tool subprocess. In this session it was
  `00-f1f4926195c5bf2c91ff57bf9710ea5a-<span>-01`, and the span id was that
  call's `claude_code.tool.execution` span in Tempo.

## Decision

`delegate-to-gemini.sh` sources `lib/delegate-telemetry.sh` and records each
call twice: one OTLP span posted to the collector's `/v1/traces`, and one JSON
line appended to `~/.local/state/delegate/gemini-calls.jsonl`.

- The span reuses the `TRACEPARENT` trace id and takes its span id as
  `parentSpanId`, so Tempo shows `delegate gemini` under the Claude tool span
  that ran the script. A missing, malformed or all-zero `TRACEPARENT` starts a
  new trace.
- `agy` itself runs with `TRACEPARENT` set to the span's own context, so a
  tracing hook inside agy would nest below it.
- Attributes: `gen_ai.provider.name`, `gen_ai.request.model`,
  `gen_ai.usage.input_tokens` and `output_tokens`, `agy.thinking_tokens`,
  `agy.cache_read_tokens`, `agy.conversation_id`, `agy.duration_seconds`,
  `delegate.profile`, `delegate.skills`, `delegate.outcome`,
  `delegate.exit_code`, `delegate.attempts`, `delegate.denied_actions`,
  `claude.session_id`. Prompt and answer text are never recorded.
- The endpoint is `DELEGATE_OTLP_ENDPOINT`, else `urls.otlpHttp` from
  `~/.config/cc-obs/endpoints.json`, else none (JSONL only).
  `DELEGATE_TELEMETRY=off` disables both.
- Recording is best effort: it never changes the script's exit status, and a
  collector that is down costs one warning and at most a 3 s timeout.
- Denial detection now reads `denied_actions` from the envelope instead of
  matching the stderr notice. The text match stays as the fallback when `jq` is
  missing and agy runs in text mode.

## Alternatives rejected

- **agy hooks as the source.** No token counts, zero-duration spans, no failure
  signal for a failed shell command, and hooks only load in trusted folders. The
  wrapper has all of that from the envelope. Hooks would still be the way to
  trace interactive `agy` sessions; this decision covers delegated calls only.
- **Metrics instead of spans.** A span carries the parent link, which is the
  point; Tempo's TraceQL aggregates the attributes. Add counters later if a
  dashboard needs rates.
- **Sending text mode output to the collector.** There are no token counts in
  text mode.

## Consequences

- A delegation can be grouped by Claude session (`claude.session_id`) or trace,
  and compared with Claude's own spend in the same Grafana.
- The wrapper needs `jq`. Without it the script works as before and records
  nothing.
- Another process that exports `TRACEPARENT` (a plain terminal) gets a root
  span per call, not a parent.

## Evidence

- Live run, 2026-10-17: the call wrote
  `trace_id f1f4926195c5bf2c91ff57bf9710ea5a` and `parent_span_id
  5f2525af87c225b4` to the JSONL, and Tempo's
  `/api/traces/f1f4926195c5bf2c91ff57bf9710ea5a` showed span `delegate gemini`
  (service `delegate-to-gemini`) whose parent was `claude_code.tool.execution`.
- `home/skills/delegation/scripts/tests/delegate-to-gemini.bats`: tests for the
  parent link, propagation to agy, new-trace cases, a down collector, the
  endpoints-file fallback, outcomes, and no text in the record.

## Revisit when

agy ships a native OTLP exporter (antigravity-cli#366), or its hooks carry
token usage. Then trace interactive sessions too, and reconsider whether the
wrapper span duplicates agy's own.
