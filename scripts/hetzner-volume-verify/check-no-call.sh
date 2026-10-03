#!/usr/bin/env bash
# Exit 0 only when the LiveKit SFU reports no participants (spec FR-009, FR-006).
# Prints calls=N, where N is livekit_participant_total summed over nodes.
# Exit 1: a call is active. Exit 3: could not tell, so treat it as a call (fail closed).
# VERIFY_METRICS_URL overrides the port-forward, for tests and for a metrics URL you already have.
set -euo pipefail

namespace=${SFU_NAMESPACE:-matrix}
service=${SFU_SERVICE:-matrix-stack-matrix-rtc-sfu}
metric=livekit_participant_total

cleanup() { [ -z "${pf_pid:-}" ] || kill "$pf_pid" 2>/dev/null || true; }
trap cleanup EXIT

url=${VERIFY_METRICS_URL:-}
if [ -z "$url" ]; then
  port=${SFU_LOCAL_PORT:-16789}
  kubectl port-forward -n "$namespace" "svc/$service" "$port:6789" >/dev/null 2>&1 &
  pf_pid=$!
  url="http://127.0.0.1:$port/metrics"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    curl -fsS --max-time 2 -o /dev/null "$url" 2>/dev/null && break
    sleep 1
  done
fi

if ! body=$(curl -fsS --max-time 10 "$url" 2>&1); then
  echo "check-no-call: cannot read $url: ${body:0:200}; treating as a call in progress" >&2
  exit 3
fi

if ! grep -qE "^${metric}[{ ]" <<<"$body"; then
  echo "check-no-call: $metric not found at $url; treating as a call in progress" >&2
  exit 3
fi

calls=$(awk -v m="$metric" '$0 ~ "^" m "[{ ]" {s += $NF} END {printf "%d", s}' <<<"$body")
echo "calls=$calls"
[ "$calls" -eq 0 ] || exit 1
