#!/usr/bin/env bash
# Sourced by delegate-to-gemini.sh. The shebang above is only for
# editor/shellcheck tooling: this file is not meant to be executed directly,
# and inherits the sourcing script's `set` options.
#
# One delegated call becomes one span, a child of the Claude Code tool span
# that ran the script (Claude exports it as TRACEPARENT to Bash subprocesses),
# so a trace query can group delegated work by the session and turn that asked
# for it. The same record is appended to a local JSONL file, which survives a
# collector that is down and works on hosts without the observability stack.
# Everything here is best effort: it never changes the script's exit status.
# Prompt and response text are never recorded, only sizes and counts.

# jq builds the records; without it, or with DELEGATE_TELEMETRY=off, there is
# nothing to record.
telemetry_enabled() {
  [[ "${DELEGATE_TELEMETRY:-on}" != "off" ]] && command -v jq >/dev/null 2>&1
}

tel_random_hex() {
  od -An -N"$1" -tx1 /dev/urandom | tr -d ' \n'
}

# GNU date prints %N as a count; BSD date prints a literal N.
tel_now_ns() {
  local ns
  ns="$(date +%s%N 2>/dev/null)"
  [[ "$ns" =~ ^[0-9]{19}$ ]] || ns="$(date +%s)000000000"
  printf '%s' "$ns"
}

# Sets tel_trace_id, tel_parent_span_id (empty for a root span), tel_span_id,
# tel_start_ns, tel_traceparent. A TRACEPARENT that is malformed or all zeros
# starts a new trace instead of being propagated.
telemetry_init() {
  tel_trace_id=""
  tel_parent_span_id=""
  if [[ "${TRACEPARENT:-}" =~ ^00-([0-9a-f]{32})-([0-9a-f]{16})-[0-9a-f]{2}$ ]]; then
    local trace="${BASH_REMATCH[1]}" span="${BASH_REMATCH[2]}"
    if [[ -n "${trace//0/}" && -n "${span//0/}" ]]; then
      tel_trace_id="$trace"
      tel_parent_span_id="$span"
    fi
  fi
  [[ -n "$tel_trace_id" ]] || tel_trace_id="$(tel_random_hex 16)"
  tel_span_id="$(tel_random_hex 8)"
  tel_start_ns="$(tel_now_ns)"
  # shellcheck disable=SC2034 # read by the sourcing script
  tel_traceparent="00-$tel_trace_id-$tel_span_id-01"
}

tel_otlp_endpoint() {
  if [[ -n "${DELEGATE_OTLP_ENDPOINT:-}" ]]; then
    printf '%s' "$DELEGATE_OTLP_ENDPOINT"
    return 0
  fi
  local file="${HOME:+$HOME/.config/cc-obs/endpoints.json}"
  if [[ -n "$file" && -f "$file" ]]; then
    jq -r '.urls.otlpHttp // empty' "$file" 2>/dev/null || true
  fi
}

# telemetry_finish <outcome> <exit-code> <model> <attempts> <profile> <skills>
#                  <envelope-json-or-empty>
# outcome: success, denied, error, auth_missing, quota, transient_exhausted,
# model_rejected. The envelope is agy's --output-format json object.
telemetry_finish() {
  local outcome="$1" exit_code="$2" model="$3" attempts="$4" profile="$5" skills="$6" envelope="$7"
  local end_ns end_iso both endpoint state_dir
  end_ns="$(tel_now_ns)"
  end_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if [[ -z "$envelope" ]] || ! jq -e . >/dev/null 2>&1 <<<"$envelope"; then
    envelope="null"
  fi

  both="$(jq -n -c \
    --arg trace "$tel_trace_id" --arg span "$tel_span_id" --arg parent "$tel_parent_span_id" \
    --arg start "$tel_start_ns" --arg end "$end_ns" --arg ts "$end_iso" \
    --arg outcome "$outcome" --argjson code "$exit_code" --arg model "$model" \
    --argjson attempts "$attempts" --arg profile "$profile" --arg skills "$skills" \
    --arg session "${CLAUDE_CODE_SESSION_ID:-}" --arg host "${HOSTNAME:-}" \
    --argjson env "$envelope" '
    def sv($k; $v): {key: $k, value: {stringValue: $v}};
    def iv($k; $v): {key: $k, value: {intValue: ($v | tostring)}};
    def dv($k; $v): {key: $k, value: {doubleValue: $v}};
    ($env.usage // {}) as $u
    | {
        record: ({
          ts: $ts, event: "delegate_gemini", outcome: $outcome, exit_code: $code,
          trace_id: $trace, span_id: $span, parent_span_id: $parent,
          claude_session_id: $session, model: $model, profile: $profile,
          skills: $skills, attempts: $attempts,
          conversation_id: ($env.conversation_id // ""),
          duration_seconds: ($env.duration_seconds // 0),
          input_tokens: ($u.input_tokens // 0), output_tokens: ($u.output_tokens // 0),
          thinking_tokens: ($u.thinking_tokens // 0), cache_read_tokens: ($u.cache_read_tokens // 0),
          denied_actions: (($env.denied_actions // []) | map(.action))
        }),
        otlp: {resourceSpans: [{
          resource: {attributes: [sv("service.name"; "delegate-to-gemini"), sv("host.name"; $host)]},
          scopeSpans: [{
            scope: {name: "delegate-to-gemini"},
            spans: [({
              traceId: $trace, spanId: $span, name: "delegate gemini", kind: 3,
              startTimeUnixNano: $start, endTimeUnixNano: $end,
              attributes: [
                sv("gen_ai.provider.name"; "google.antigravity"),
                sv("gen_ai.request.model"; $model),
                iv("gen_ai.usage.input_tokens"; ($u.input_tokens // 0)),
                iv("gen_ai.usage.output_tokens"; ($u.output_tokens // 0)),
                iv("agy.thinking_tokens"; ($u.thinking_tokens // 0)),
                iv("agy.cache_read_tokens"; ($u.cache_read_tokens // 0)),
                sv("agy.conversation_id"; ($env.conversation_id // "")),
                dv("agy.duration_seconds"; ($env.duration_seconds // 0)),
                sv("delegate.profile"; $profile),
                sv("delegate.skills"; $skills),
                sv("delegate.outcome"; $outcome),
                iv("delegate.exit_code"; $code),
                iv("delegate.attempts"; $attempts),
                sv("delegate.denied_actions"; (($env.denied_actions // []) | map(.action) | join(","))),
                sv("claude.session_id"; $session)
              ],
              status: (if $outcome == "success" then {code: 1} else {code: 2, message: $outcome} end)
            } + (if $parent != "" then {parentSpanId: $parent} else {} end))]
          }]
        }]}
      }' 2>/dev/null)" || return 0
  [[ -n "$both" ]] || return 0

  if [[ -n "${DELEGATE_TELEMETRY_DIR:-}" ]]; then
    state_dir="$DELEGATE_TELEMETRY_DIR"
  elif [[ -n "${XDG_STATE_HOME:-}" ]]; then
    state_dir="$XDG_STATE_HOME/delegate"
  elif [[ -n "${HOME:-}" ]]; then
    state_dir="$HOME/.local/state/delegate"
  else
    state_dir=""
  fi
  if [[ -n "$state_dir" ]]; then
    mkdir -p "$state_dir" 2>/dev/null &&
      jq -c .record <<<"$both" >>"$state_dir/gemini-calls.jsonl" 2>/dev/null ||
      echo "warning: could not append the delegate record under $state_dir" >&2
  fi

  endpoint="$(tel_otlp_endpoint)"
  if [[ -n "$endpoint" ]]; then
    curl -sS --max-time 3 -H 'Content-Type: application/json' \
      -d "$(jq -c .otlp <<<"$both")" "${endpoint%/}/v1/traces" >/dev/null 2>&1 ||
      echo "warning: could not send the delegate span to $endpoint (the JSONL record was still written)" >&2
  fi
  return 0
}
