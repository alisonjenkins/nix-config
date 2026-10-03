#!/usr/bin/env bash
# Exit 0 only when no LiveKit SFU reports a participant (spec FR-009, FR-006).
# Prints calls=N, where N is livekit_participant_total summed over every SFU pod and series.
# Exit 1: a call is active. Exit 3: could not read every SFU, so treat it as a call (fail closed).
# VERIFY_METRICS_URLS (space separated) replaces the port-forwards, for tests and for URLs you already have.
set -euo pipefail

namespace=${SFU_NAMESPACE:-matrix}
selector=${SFU_SELECTOR:-app.kubernetes.io/component=matrix-rtc-voip-server}
metric=livekit_participant_total
port=${SFU_LOCAL_PORT:-16789}

pf_pid=""
cleanup() { [ -z "$pf_pid" ] || kill "$pf_pid" 2>/dev/null || true; }
trap cleanup EXIT

fail_closed() {
  echo "check-no-call: $1; treating as a call in progress" >&2
  exit 3
}

# read_metrics URL: print the body or fail closed.
read_metrics() {
  local body
  body=$(curl -fsS --max-time 10 "$1" 2>&1) || fail_closed "cannot read $1: ${body:0:200}"
  grep -qE "^${metric}[{ ]" <<<"$body" || fail_closed "$metric not found at $1"
  printf '%s\n' "$body"
}

bodies=()
if [ -n "${VERIFY_METRICS_URLS:-}" ]; then
  for url in $VERIFY_METRICS_URLS; do
    bodies+=("$(read_metrics "$url")")
  done
else
  pods=$(kubectl get pods -n "$namespace" -l "$selector" -o name 2>&1) \
    || fail_closed "cannot list SFU pods ($selector) in $namespace: ${pods:0:200}"
  [ -n "$pods" ] || fail_closed "no SFU pod matches $selector in $namespace"
  for pod in $pods; do
    kubectl port-forward -n "$namespace" "$pod" "$port:6789" >/dev/null 2>&1 &
    pf_pid=$!
    url="http://127.0.0.1:$port/metrics"
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      curl -fsS --max-time 2 -o /dev/null "$url" 2>/dev/null && break
      sleep 1
    done
    bodies+=("$(read_metrics "$url")")
    cleanup
    pf_pid=""
  done
fi

calls=0
for body in "${bodies[@]}"; do
  n=$(awk -v m="$metric" '$0 ~ "^" m "[{ ]" {s += $NF} END {printf "%d", s}' <<<"$body")
  calls=$((calls + n))
done
echo "calls=$calls"
[ "$calls" -eq 0 ] || exit 1
